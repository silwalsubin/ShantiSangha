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
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Agent.Controllers;

[ApiController]
[Authorize]
[Route("api/agent")]
public class AgentController(
    AgentOrchestrator orchestrator,
    AgentDbContext db,
    ICurrentUser currentUser,
    IReflectionQueryService reflections,
    ILogger<AgentController> logger) : ControllerBase
{
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
            await foreach (var chunk in orchestrator.StreamAsync(body.Message, cancellationToken))
            {
                await WriteChunkAsync(chunk, cancellationToken);
            }
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            await WriteChunkAsync(
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
            await WriteChunkAsync(FriendlyMessageFor(ex), CancellationToken.None);
        }

        await HttpContext.Response.WriteAsync("data: [DONE]\n\n", Encoding.UTF8, CancellationToken.None);
        await HttpContext.Response.Body.FlushAsync(CancellationToken.None);
    }

    private async Task WriteChunkAsync(string text, CancellationToken ct)
    {
        var payload = JsonSerializer.Serialize(text);
        await HttpContext.Response.WriteAsync($"data: {payload}\n\n", Encoding.UTF8, ct);
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

        var messages = await db.AgentMessages
            .Where(m => m.UserId == user.Id)
            .OrderBy(m => m.CreatedAt)
            .Select(m => new
            {
                id = m.Id,
                role = m.Role == AgentMessageRole.User ? "user" : "assistant",
                content = m.Content,
                createdAt = m.CreatedAt,
            })
            .ToListAsync(ct);

        return Ok(messages);
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

    /// <summary>
    /// Seed today's morning reflection as the first assistant turn if the
    /// user hasn't seen anything from the agent yet today. Idempotent —
    /// safe to call on every screen mount. The greeting is persisted in
    /// AgentMessages so it counts toward the replay window and survives
    /// reloads.
    /// </summary>
    [HttpPost("morning")]
    public async Task<IActionResult> Morning(CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        // "Today" approximated as UTC midnight. iOS-local TZ refinements
        // can come later — V1 just gates against same-UTC-day repeats.
        var todayUtc = DateTime.UtcNow.Date;
        var alreadyGreeted = await db.AgentMessages
            .AnyAsync(m =>
                m.UserId == user.Id &&
                m.Role == AgentMessageRole.Assistant &&
                m.CreatedAt >= todayUtc, ct);

        if (alreadyGreeted)
        {
            return Ok(new { greeted = true });
        }

        var reflection = await reflections.GetRecentReflectionAsync(user.Id, ct);
        if (string.IsNullOrWhiteSpace(reflection))
        {
            return Ok(new { greeted = false, message = (object?)null });
        }

        var content = $"Good morning. Here's the reflection for today:\n\n{reflection.Trim()}";

        var row = new AgentMessage
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            Role = AgentMessageRole.Assistant,
            Content = content,
            CreatedAt = DateTime.UtcNow,
        };
        db.AgentMessages.Add(row);
        await db.SaveChangesAsync(ct);

        return Ok(new
        {
            greeted = false,
            message = new { role = "assistant", content = row.Content },
        });
    }
}
