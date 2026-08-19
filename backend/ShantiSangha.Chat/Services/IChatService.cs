namespace ShantiSangha.Chat.Services;

public interface IChatService
{
    IAsyncEnumerable<string> StreamResponseAsync(
        Guid userId,
        Guid conversationId,
        string userMessage,
        CancellationToken cancellationToken = default);

    /// The companion speaks first: streams a short personalized greeting into
    /// an empty conversation, drawn from the user's recent memory. Yields
    /// nothing if the conversation already has messages.
    IAsyncEnumerable<string> StreamOpenerAsync(
        Guid userId,
        Guid conversationId,
        CancellationToken cancellationToken = default);
}
