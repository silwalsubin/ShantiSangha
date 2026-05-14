using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Agent.AI;
using ShantiSangha.Agent.Contracts;
using ShantiSangha.Agent.Data;
using ShantiSangha.Agent.Models;
using ShantiSangha.Reminders.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Agent.Controllers;

[ApiController]
[Authorize]
[Route("api/agent")]
public class AgentController(
    AgentOrchestrator orchestrator,
    AgentDbContext db,
    ICurrentUser currentUser,
    IReminderService reminders,
    ILogger<AgentController> logger) : ControllerBase
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [HttpPost("chat")]
    public async Task Chat(
        [FromBody] AgentChatRequest body,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(body?.Message))
        {
            HttpContext.Response.StatusCode = 400;
            return;
        }

        HttpContext.Response.Headers.ContentType = "text/event-stream";
        HttpContext.Response.Headers.CacheControl = "no-cache";
        HttpContext.Response.Headers.Connection = "keep-alive";

        try
        {
            await foreach (var evt in orchestrator.StreamAsync(body.Message, cancellationToken))
            {
                switch (evt)
                {
                    case AgentStreamEvent.Text text:
                        await WriteTextChunkAsync(text.Chunk, cancellationToken);
                        break;
                    case AgentStreamEvent.Reminders r:
                        await WriteRemindersAsync(r.Items, cancellationToken);
                        break;
                }
            }
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            await WriteTextChunkAsync(
                "\n\n(That took longer than expected. Please try again with a shorter request.)",
                cancellationToken);
        }
        catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            // SSE headers have already been flushed by this point, so we can't
            // return a 500. Surface a clean line to the client so the typing
            // indicator resolves instead of hanging forever, and log details
            // server-side for diagnosis.
            logger.LogError(ex, "Agent chat failed mid-stream");
            await WriteTextChunkAsync(FriendlyMessageFor(ex), CancellationToken.None);
        }

        await HttpContext.Response.WriteAsync("data: [DONE]\n\n", Encoding.UTF8, CancellationToken.None);
        await HttpContext.Response.Body.FlushAsync(CancellationToken.None);
    }

    private async Task WriteTextChunkAsync(string text, CancellationToken ct)
    {
        var payload = JsonSerializer.Serialize(text);
        await HttpContext.Response.WriteAsync($"data: {payload}\n\n", Encoding.UTF8, ct);
        await HttpContext.Response.Body.FlushAsync(ct);
    }

    private async Task WriteRemindersAsync(
        IReadOnlyList<Reminders.Contracts.ReminderResponse> items, CancellationToken ct)
    {
        var payload = JsonSerializer.Serialize(items, JsonOptions);
        await HttpContext.Response.WriteAsync(
            $"event: reminders\ndata: {payload}\n\n", Encoding.UTF8, ct);
        await HttpContext.Response.Body.FlushAsync(ct);
    }

    private static string FriendlyMessageFor(Exception ex)
    {
        var message = ex.Message ?? "";
        if (message.Contains("insufficient_quota", StringComparison.OrdinalIgnoreCase)
            || message.Contains("429", StringComparison.Ordinal))
        {
            return "I'm temporarily unavailable — the language model is out of capacity. Please try again later.";
        }
        return "Something went wrong. Please try again.";
    }

    [HttpGet("messages")]
    public async Task<IActionResult> GetMessages(CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var rows = await db.AgentMessages
            .Where(m => m.UserId == user.Id)
            .OrderBy(m => m.CreatedAt)
            .Select(m => new
            {
                m.Id,
                m.Role,
                m.Content,
                m.Attachments,
                m.CreatedAt,
            })
            .ToListAsync(ct);

        // Expand attachments per row. The agent surfaces stale reminders by
        // re-querying live state on each fetch, so cards always show today's
        // truth — completed/deleted reminders simply drop out.
        var allReminderIds = rows
            .Select(r => AgentMessageAttachmentsCodec.Decode(r.Attachments)?.ReminderIds)
            .Where(ids => ids is not null && ids.Count > 0)
            .SelectMany(ids => ids!)
            .Distinct()
            .ToList();

        Dictionary<Guid, Reminders.Contracts.ReminderResponse>? reminderLookup = null;
        if (allReminderIds.Count > 0)
        {
            var all = await reminders.ListAsync(user.Id, connectionId: null, date: null, ct);
            reminderLookup = all
                .Where(r => allReminderIds.Contains(r.Id))
                .ToDictionary(r => r.Id);
        }

        var result = rows.Select(m =>
        {
            var ids = AgentMessageAttachmentsCodec.Decode(m.Attachments)?.ReminderIds;
            var attachedReminders = ids is null || reminderLookup is null
                ? Array.Empty<Reminders.Contracts.ReminderResponse>()
                : ids
                    .Where(id => reminderLookup.ContainsKey(id))
                    .Select(id => reminderLookup[id])
                    .ToArray();

            return new
            {
                id = m.Id,
                role = m.Role == AgentMessageRole.User ? "user" : "assistant",
                content = m.Content,
                attachedReminders,
                createdAt = m.CreatedAt,
            };
        }).ToList();

        return Ok(result);
    }

    [HttpDelete("messages")]
    public async Task<IActionResult> ClearMessages(CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        await db.AgentMessages
            .Where(m => m.UserId == user.Id)
            .ExecuteDeleteAsync(ct);

        return NoContent();
    }

}
