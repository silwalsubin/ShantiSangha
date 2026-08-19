namespace ShantiSangha.Shared.Interfaces;

/// Minimal realtime fan-out surface, exposed in Shared so any module can
/// broadcast over the existing chat WebSocket hub without depending on the
/// Friends module. Implemented by `RedisChatRealtimeHub` (Friends), which also
/// implements the richer `IChatRealtimeHub`. `conversationId` is the channel
/// clients subscribe to (e.g. a friendship id).
public interface IRealtimeBroadcaster
{
    Task PublishAsync(Guid conversationId, string kind, object payload, CancellationToken ct = default);
}
