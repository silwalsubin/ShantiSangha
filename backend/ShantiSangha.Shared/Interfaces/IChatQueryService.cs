using ShantiSangha.Shared.Models;

namespace ShantiSangha.Shared.Interfaces;

public interface IChatQueryService
{
    Task<string?> GetConversationTranscriptAsync(Guid conversationId, CancellationToken ct = default);
    Task<int> GetMessageCountAsync(Guid conversationId, CancellationToken ct = default);
    Task<IReadOnlyList<ChatMessageDto>> GetMessagesAsync(IReadOnlyCollection<Guid> messageIds, CancellationToken ct = default);

    /// (messageId, owning userId) for every user-authored message of at least
    /// minLength characters — used by the Memory module's one-time backfill.
    Task<IReadOnlyList<UserMessageRef>> GetAllUserMessageRefsAsync(int minLength, CancellationToken ct = default);
}
