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
    IConversationStore conversations,
    ICurrentUser currentUser,
    IReminderService reminders,
    Storage.AgentMediaStorage mediaStorage,
    ILogger<AgentController> logger) : ControllerBase
{
    private const string ThreadType = "assistant";
    private static readonly TimeSpan ImageUrlLifetime = TimeSpan.FromHours(6);

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [HttpPost("chat")]
    public async Task Chat(
        [FromBody] AgentChatRequest body,
        CancellationToken cancellationToken)
    {
        // A turn must carry text, an image, or both.
        if (string.IsNullOrWhiteSpace(body?.Message)
            && string.IsNullOrWhiteSpace(body?.ImageBase64))
        {
            HttpContext.Response.StatusCode = 400;
            return;
        }

        byte[]? imageBytes = null;
        if (!string.IsNullOrWhiteSpace(body!.ImageBase64))
        {
            try { imageBytes = Convert.FromBase64String(body.ImageBase64); }
            catch (FormatException)
            {
                // Malformed image — proceed text-only rather than 400 so a
                // bad attachment doesn't swallow the user's question.
                imageBytes = null;
            }
        }

        HttpContext.Response.Headers.ContentType = "text/event-stream";
        HttpContext.Response.Headers.CacheControl = "no-cache";
        HttpContext.Response.Headers.Connection = "keep-alive";

        try
        {
            await foreach (var evt in orchestrator.StreamAsync(
                body.Message ?? string.Empty, imageBytes, body.ImageContentType, body.ReminderId, body.History, body.ConversationId, cancellationToken))
            {
                switch (evt)
                {
                    case AgentStreamEvent.Text text:
                        await WriteTextChunkAsync(text.Chunk, cancellationToken);
                        break;
                    case AgentStreamEvent.Reminders r:
                        await WriteRemindersAsync(r.Items, cancellationToken);
                        break;
                    case AgentStreamEvent.QuickActions qa:
                        await WriteQuickActionsAsync(qa.Items, cancellationToken);
                        break;
                    case AgentStreamEvent.Conversation conv:
                        await WriteConversationAsync(conv.Id, cancellationToken);
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

    private async Task WriteConversationAsync(Guid id, CancellationToken ct)
    {
        // Unknown event names are silently ignored by older clients, so this
        // frame is backward-compatible.
        var payload = JsonSerializer.Serialize(new { id }, JsonOptions);
        await HttpContext.Response.WriteAsync(
            $"event: conversation\ndata: {payload}\n\n", Encoding.UTF8, ct);
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

    private async Task WriteQuickActionsAsync(
        IReadOnlyList<Contracts.QuickAction> items, CancellationToken ct)
    {
        var payload = JsonSerializer.Serialize(items, JsonOptions);
        await HttpContext.Response.WriteAsync(
            $"event: quick_actions\ndata: {payload}\n\n", Encoding.UTF8, ct);
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

    /// Thread list, newest-activity first.
    [HttpGet("conversations")]
    public async Task<IActionResult> ListConversations(CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var threads = await conversations.ListConversationsAsync(user.Id, ThreadType, ct);
        return Ok(threads.Select(t => new
        {
            id = t.Id,
            title = t.Title,
            createdAt = t.CreatedAt,
            updatedAt = t.UpdatedAt,
            lastMessage = t.LastMessage,
        }));
    }

    /// Starts a fresh thread; it gets its title from the first message.
    [HttpPost("conversations")]
    public async Task<IActionResult> CreateConversation(CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var id = await conversations.CreateConversationAsync(user.Id, ThreadType, null, ct);
        return Ok(new { id });
    }

    /// Deletes one thread and the S3 bytes of any photos shared in it.
    [HttpDelete("conversations/{id:guid}")]
    public async Task<IActionResult> DeleteConversation(Guid id, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var metadata = await conversations.DeleteConversationAsync(id, user.Id, ct);
        if (metadata is null) return NotFound();

        await DeleteImagesFromMetadataAsync(metadata, ct);
        return NoContent();
    }

    /// One thread's messages (or the most recent thread when `conversationId`
    /// is omitted — which is also what pre-thread clients get).
    [HttpGet("messages")]
    public async Task<IActionResult> GetMessages(
        [FromQuery] Guid? conversationId = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        Guid? threadId = conversationId;
        if (threadId is Guid requested)
        {
            if (!await conversations.ConversationBelongsToUserAsync(requested, user.Id, ThreadType, ct))
                return NotFound();
        }
        else
        {
            threadId = await conversations.GetLatestConversationIdAsync(user.Id, ThreadType, ct);
        }

        if (threadId is null) return Ok(Array.Empty<object>());

        var rows = await conversations.GetMessagesAsync(threadId.Value, null, ct);

        // Expand reminder attachments by re-querying live state on each fetch,
        // so cards always show today's truth — completed/deleted reminders
        // simply drop out.
        var decoded = rows
            .Select(m => (Message: m, Metadata: AgentMessageMetadataCodec.Decode(m.MetadataJson)))
            .ToList();

        var allReminderIds = decoded
            .Select(d => d.Metadata?.ReminderIds)
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

        var result = new List<object>(decoded.Count);
        foreach (var (m, metadata) in decoded)
        {
            var ids = metadata?.ReminderIds;
            var attachedReminders = ids is null || reminderLookup is null
                ? Array.Empty<Reminders.Contracts.ReminderResponse>()
                : ids
                    .Where(id => reminderLookup.ContainsKey(id))
                    .Select(id => reminderLookup[id])
                    .ToArray();

            // Re-issue a presigned GET each load (the stored key is stable;
            // the URL expires). Best-effort — a presign failure just drops
            // the image rather than failing the whole history fetch.
            string? imageUrl = null;
            if (!string.IsNullOrWhiteSpace(metadata?.ImageObjectKey))
            {
                try
                {
                    imageUrl = await mediaStorage.GetPresignedDownloadUrlAsync(metadata!.ImageObjectKey!, ImageUrlLifetime);
                }
                catch (Exception ex)
                {
                    logger.LogWarning(ex, "Failed to presign agent image for message {MessageId}", m.Id);
                }
            }

            result.Add(new
            {
                id = m.Id,
                conversationId = m.ConversationId,
                role = string.Equals(m.Role, "User", StringComparison.OrdinalIgnoreCase) ? "user" : "assistant",
                content = m.Content,
                attachedReminders,
                imageUrl,
                createdAt = m.CreatedAt,
            });
        }

        return Ok(result);
    }

    /// Legacy clear-everything (pre-thread clients): deletes ALL assistant
    /// threads and their photo bytes.
    [HttpDelete("messages")]
    public async Task<IActionResult> ClearMessages(CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var threads = await conversations.ListConversationsAsync(user.Id, ThreadType, ct);
        foreach (var thread in threads)
        {
            var metadata = await conversations.DeleteConversationAsync(thread.Id, user.Id, ct);
            if (metadata is not null)
                await DeleteImagesFromMetadataAsync(metadata, ct);
        }

        return NoContent();
    }

    /// S3 cleanup for deleted threads — best-effort (logged, not thrown).
    private async Task DeleteImagesFromMetadataAsync(IReadOnlyList<string> metadataBlobs, CancellationToken ct)
    {
        var imageKeys = metadataBlobs
            .Select(blob => AgentMessageMetadataCodec.Decode(blob)?.ImageObjectKey)
            .Where(key => !string.IsNullOrWhiteSpace(key))
            .Select(key => key!)
            .Distinct()
            .ToList();

        if (imageKeys.Count == 0) return;

        try
        {
            await mediaStorage.DeleteManyAsync(imageKeys, ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to delete agent images for removed thread(s)");
        }
    }
}
