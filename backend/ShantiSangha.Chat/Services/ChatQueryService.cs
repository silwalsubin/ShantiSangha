using Microsoft.EntityFrameworkCore;
using ShantiSangha.Chat.Data;
using ShantiSangha.Chat.Models;
using ShantiSangha.Shared.Interfaces;

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
}
