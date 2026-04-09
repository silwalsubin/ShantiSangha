namespace ShantiSangha.Shared.Interfaces;

public interface IChatQueryService
{
    Task<string?> GetConversationTranscriptAsync(Guid conversationId, CancellationToken ct = default);
    Task<int> GetMessageCountAsync(Guid conversationId, CancellationToken ct = default);
}
