using Microsoft.EntityFrameworkCore;
using ShantiSangha.Chat.Data;
using ShantiSangha.Chat.Models;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Models;

namespace ShantiSangha.Chat.Services;

public class ChatQueryService(ChatDbContext db) : IChatQueryService
{
    public async Task<string?> GetConversationTranscriptAsync(
        Guid conversationId, CancellationToken ct = default)
    {
        var messages = await db.Messages
            .Where(m => m.ConversationId == conversationId)
            .OrderBy(m => m.CreatedAt)
            .ToListAsync(ct);

        if (messages.Count == 0) return null;

        return string.Join("\n", messages.Select(m =>
            $"{(m.Role == MessageRole.User ? "User" : "ShantiSangha")}: {m.Content}"));
    }

    public async Task<int> GetMessageCountAsync(
        Guid conversationId, CancellationToken ct = default)
    {
        return await db.Messages.CountAsync(m => m.ConversationId == conversationId, ct);
    }

    public async Task<IReadOnlyList<ChatMessageDto>> GetMessagesAsync(
        IReadOnlyCollection<Guid> messageIds, CancellationToken ct = default)
    {
        return await db.Messages
            .Where(m => messageIds.Contains(m.Id))
            .Select(m => new ChatMessageDto(
                m.Id,
                m.ConversationId,
                m.Role == MessageRole.User ? "User" : "Assistant",
                m.Content,
                m.CreatedAt))
            .ToListAsync(ct);
    }

    public async Task<IReadOnlyList<UserMessageRef>> GetAllUserMessageRefsAsync(
        int minLength, CancellationToken ct = default)
    {
        // Companion (Reflect) threads only: assistant threads are task
        // chatter, deliberately never memory-indexed (see IConversationStore).
        return await db.Messages
            .Where(m => m.Role == MessageRole.User && m.Content.Length >= minLength)
            .Join(db.Conversations,
                m => m.ConversationId,
                c => c.Id,
                (m, c) => new { m, c })
            .Where(x => x.c.Type == ConversationType.General)
            .Select(x => new UserMessageRef(x.m.Id, x.c.UserId))
            .ToListAsync(ct);
    }
}
