using Microsoft.EntityFrameworkCore;
using ShantiSangha.Chat.Data;
using ShantiSangha.Chat.Models;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Models;

namespace ShantiSangha.Chat.Services;

/// The Chat module's implementation of the unified conversation store.
/// See IConversationStore for the contract (and for why appends here do NOT
/// publish MessagesSavedEvent).
public class ConversationStore(ChatDbContext db) : IConversationStore
{
    public async Task<Guid> CreateConversationAsync(
        Guid userId, string type, string? title = null, CancellationToken ct = default)
    {
        var conversation = new Conversation
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Title = title,
            Type = type,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        db.Conversations.Add(conversation);
        await db.SaveChangesAsync(ct);
        return conversation.Id;
    }

    public async Task<IReadOnlyList<ConversationSummary>> ListConversationsAsync(
        Guid userId, string type, CancellationToken ct = default)
    {
        return await db.Conversations
            .Where(c => c.UserId == userId && c.Type == type)
            .OrderByDescending(c => c.UpdatedAt)
            .Select(c => new ConversationSummary(
                c.Id,
                c.Title,
                c.CreatedAt,
                c.UpdatedAt,
                db.Messages
                    .Where(m => m.ConversationId == c.Id)
                    .OrderByDescending(m => m.CreatedAt)
                    .Select(m => m.Content)
                    .FirstOrDefault() ?? ""))
            .ToListAsync(ct);
    }

    public async Task<Guid?> GetLatestConversationIdAsync(
        Guid userId, string type, CancellationToken ct = default)
    {
        var id = await db.Conversations
            .Where(c => c.UserId == userId && c.Type == type)
            .OrderByDescending(c => c.UpdatedAt)
            .Select(c => (Guid?)c.Id)
            .FirstOrDefaultAsync(ct);
        return id;
    }

    public async Task<bool> ConversationBelongsToUserAsync(
        Guid conversationId, Guid userId, string type, CancellationToken ct = default)
    {
        return await db.Conversations
            .AnyAsync(c => c.Id == conversationId && c.UserId == userId && c.Type == type, ct);
    }

    public async Task<IReadOnlyList<StoredChatMessage>> GetMessagesAsync(
        Guid conversationId, int? takeLast = null, CancellationToken ct = default)
    {
        var query = db.Messages.Where(m => m.ConversationId == conversationId);

        List<Message> rows;
        if (takeLast is int n)
        {
            rows = await query
                .OrderByDescending(m => m.CreatedAt)
                .Take(n)
                .OrderBy(m => m.CreatedAt)
                .ToListAsync(ct);
        }
        else
        {
            rows = await query.OrderBy(m => m.CreatedAt).ToListAsync(ct);
        }

        return rows
            .Select(m => new StoredChatMessage(
                m.Id, m.ConversationId, m.Role.ToString(), m.Content, m.CreatedAt, m.MetadataJson))
            .ToList();
    }

    public async Task AppendMessageAsync(
        Guid conversationId, Guid messageId, string role, string content,
        string? metadataJson = null, CancellationToken ct = default)
    {
        db.Messages.Add(new Message
        {
            Id = messageId,
            ConversationId = conversationId,
            Role = string.Equals(role, "user", StringComparison.OrdinalIgnoreCase)
                ? MessageRole.User
                : MessageRole.Assistant,
            Content = content,
            MetadataJson = metadataJson,
            CreatedAt = DateTime.UtcNow
        });

        var conversation = await db.Conversations.FindAsync([conversationId], ct);
        if (conversation is not null)
            conversation.UpdatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync(ct);
    }

    public async Task SetTitleIfEmptyAsync(
        Guid conversationId, string title, CancellationToken ct = default)
    {
        var conversation = await db.Conversations.FindAsync([conversationId], ct);
        if (conversation is null || !string.IsNullOrWhiteSpace(conversation.Title)) return;
        conversation.Title = title;
        await db.SaveChangesAsync(ct);
    }

    public async Task<IReadOnlyList<string>?> DeleteConversationAsync(
        Guid conversationId, Guid userId, CancellationToken ct = default)
    {
        var conversation = await db.Conversations
            .FirstOrDefaultAsync(c => c.Id == conversationId && c.UserId == userId, ct);
        if (conversation is null) return null;

        var metadata = await db.Messages
            .Where(m => m.ConversationId == conversationId && m.MetadataJson != null)
            .Select(m => m.MetadataJson!)
            .ToListAsync(ct);

        await db.Messages.Where(m => m.ConversationId == conversationId).ExecuteDeleteAsync(ct);
        db.Conversations.Remove(conversation);
        await db.SaveChangesAsync(ct);

        return metadata;
    }
}
