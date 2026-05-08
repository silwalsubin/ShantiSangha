using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Chat.Contracts;
using ShantiSangha.Chat.Data;
using ShantiSangha.Chat.Models;
using ShantiSangha.Chat.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Chat.Controllers;

[ApiController]
[Authorize]
[Route("api/conversations")]
public class ConversationsController(
    ChatDbContext db,
    IChatService chatService,
    IBirthDetailShareService shareService,
    ICurrentUser currentUser) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> ListConversations(CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var conversations = await db.Conversations
            .Where(c => c.UserId == user.Id)
            .OrderByDescending(c => c.UpdatedAt)
            .Select(c => new
            {
                c.Id,
                c.Title,
                c.CreatedAt,
                c.UpdatedAt,
                LastMessage = db.Messages
                    .Where(m => m.ConversationId == c.Id)
                    .OrderByDescending(m => m.CreatedAt)
                    .Select(m => m.Content)
                    .FirstOrDefault(),
                LastUserMessage = db.Messages
                    .Where(m => m.ConversationId == c.Id && m.Role == MessageRole.User)
                    .OrderByDescending(m => m.CreatedAt)
                    .Select(m => m.Content)
                    .FirstOrDefault()
            })
            .ToListAsync(ct);

        return Ok(conversations);
    }

    [HttpPost]
    public async Task<IActionResult> CreateConversation(
        [FromBody] CreateConversationRequest? request,
        CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var title = request?.Title?.Trim();
        if (string.IsNullOrWhiteSpace(title)) title = null;

        var rawType = request?.Type?.Trim();
        var type = ConversationType.General;
        if (string.Equals(rawType, ConversationType.Chart, StringComparison.OrdinalIgnoreCase))
            type = ConversationType.Chart;
        else if (string.Equals(rawType, ConversationType.Pair, StringComparison.OrdinalIgnoreCase))
            type = ConversationType.Pair;

        Guid? subjectUserId = null;
        if (type == ConversationType.Pair)
        {
            // A pair conversation is meaningless without a subject; bail
            // before creating an orphan row.
            if (request?.SubjectUserId is null || request.SubjectUserId == Guid.Empty)
                return BadRequest(new { error = "subjectUserId required for pair conversations" });

            if (request.SubjectUserId == user.Id)
                return BadRequest(new { error = "subject must be another user" });

            // Same gate as the pair-reading endpoint: viewer must have an
            // active BirthDetailShare from the subject.
            if (!await shareService.HasAccessAsync(user.Id, request.SubjectUserId.Value, ct))
                return Forbid();

            subjectUserId = request.SubjectUserId.Value;
        }

        var conversation = new Conversation
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            Title = title,
            Type = type,
            SubjectUserId = subjectUserId,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        db.Conversations.Add(conversation);
        await db.SaveChangesAsync(ct);

        return Created($"/conversations/{conversation.Id}",
            new { conversation.Id, conversation.Title, conversation.Type, conversation.SubjectUserId, conversation.CreatedAt });
    }

    public record CreateConversationRequest(string? Title, string? Type = null, Guid? SubjectUserId = null);

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetConversation(Guid id, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var conversation = await db.Conversations
            .Where(c => c.Id == id && c.UserId == user.Id)
            .Select(c => new
            {
                c.Id,
                c.Title,
                c.CreatedAt,
                c.UpdatedAt,
                Messages = db.Messages
                    .Where(m => m.ConversationId == c.Id)
                    .OrderBy(m => m.CreatedAt)
                    .Select(m => new { m.Id, m.Role, m.Content, m.CreatedAt })
                    .ToList()
            })
            .FirstOrDefaultAsync(ct);

        return conversation is null ? NotFound() : Ok(conversation);
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> DeleteConversation(Guid id, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var conversation = await db.Conversations
            .FirstOrDefaultAsync(c => c.Id == id && c.UserId == user.Id, ct);

        if (conversation is null) return NotFound();

        db.Conversations.Remove(conversation);
        await db.SaveChangesAsync(ct);

        return NoContent();
    }

    [HttpPost("{id:guid}/messages")]
    public async Task SendMessage(
        Guid id,
        [FromBody] SendMessageRequest body,
        CancellationToken cancellationToken)
    {
        var user = await currentUser.GetAsync();
        if (user is null)
        {
            HttpContext.Response.StatusCode = 401;
            return;
        }

        var conversation = await db.Conversations
            .FirstOrDefaultAsync(c => c.Id == id && c.UserId == user.Id, cancellationToken);

        if (conversation is null)
        {
            HttpContext.Response.StatusCode = 404;
            return;
        }

        // Pair conversations re-check share access on every send so that a
        // revoked grant stops the data flow immediately, even on a
        // pre-existing conversation row. The row itself stays — the private
        // user-side history isn't subject's data — but the LLM stops being
        // given the subject's chart facts.
        if (conversation.Type == ConversationType.Pair && conversation.SubjectUserId is { } subjectId)
        {
            var stillShared = await shareService.HasAccessAsync(user.Id, subjectId, cancellationToken);
            if (!stillShared)
            {
                HttpContext.Response.StatusCode = 403;
                return;
            }
        }

        // SSE headers
        HttpContext.Response.Headers.ContentType = "text/event-stream";
        HttpContext.Response.Headers.CacheControl = "no-cache";
        HttpContext.Response.Headers.Connection = "keep-alive";

        await foreach (var chunk in chatService.StreamResponseAsync(
            user.Id, id, body.Content, cancellationToken))
        {
            // JSON-serialize the chunk so embedded newlines, quotes, and other
            // control characters survive SSE framing intact. Client JSON-decodes
            // each payload back to the original string.
            var payload = JsonSerializer.Serialize(chunk);
            var line = $"data: {payload}\n\n";
            await HttpContext.Response.WriteAsync(line, Encoding.UTF8, cancellationToken);
            await HttpContext.Response.Body.FlushAsync(cancellationToken);
        }

        await HttpContext.Response.WriteAsync("data: [DONE]\n\n", Encoding.UTF8, cancellationToken);
        await HttpContext.Response.Body.FlushAsync(cancellationToken);
    }
}
