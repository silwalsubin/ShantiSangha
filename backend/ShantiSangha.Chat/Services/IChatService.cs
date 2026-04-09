namespace ShantiSangha.Chat.Services;

public interface IChatService
{
    IAsyncEnumerable<string> StreamResponseAsync(
        Guid userId,
        Guid conversationId,
        string userMessage,
        CancellationToken cancellationToken = default);
}
