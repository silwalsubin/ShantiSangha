using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace ShantiSangha.Friends.Realtime;

/// <summary>
/// Thread-safe in-process hub. Stores one record per live subscriber:
/// `(socket → (userId, conversationId))`. Lookups for publish go via a
/// secondary index keyed on conversationId so fan-out is O(subscribers
/// in conversation), not O(all subscribers).
///
/// Single-instance only. When we scale to multiple ECS tasks, swap this
/// for a Redis-pub/sub-backed implementation — same interface, no
/// caller changes.
/// </summary>
public class InMemoryChatRealtimeHub(ILogger<InMemoryChatRealtimeHub> logger) : IChatRealtimeHub
{
    private record Subscriber(Guid UserId, Guid ConversationId, WebSocket Socket);

    // socket → subscriber. Lets us unregister cheaply on disconnect.
    private readonly ConcurrentDictionary<WebSocket, Subscriber> _bySocket = new();

    // conversationId → set of sockets. Lets us publish without scanning.
    // Inner ConcurrentDictionary used as a set (key = socket, value ignored).
    private readonly ConcurrentDictionary<Guid, ConcurrentDictionary<WebSocket, byte>> _byConversation = new();

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public void Register(Guid userId, Guid conversationId, WebSocket socket)
    {
        var subscriber = new Subscriber(userId, conversationId, socket);
        _bySocket[socket] = subscriber;
        var bucket = _byConversation.GetOrAdd(conversationId, _ => new ConcurrentDictionary<WebSocket, byte>());
        bucket[socket] = 0;
        logger.LogDebug(
            "realtime.subscribe user={UserId} conversation={ConversationId} sockets={Count}",
            userId, conversationId, bucket.Count);
    }

    public void Unregister(WebSocket socket)
    {
        if (_bySocket.TryRemove(socket, out var subscriber))
        {
            if (_byConversation.TryGetValue(subscriber.ConversationId, out var bucket))
            {
                bucket.TryRemove(socket, out _);
                if (bucket.IsEmpty)
                {
                    _byConversation.TryRemove(subscriber.ConversationId, out _);
                }
            }
            logger.LogDebug(
                "realtime.unsubscribe user={UserId} conversation={ConversationId}",
                subscriber.UserId, subscriber.ConversationId);
        }
    }

    public async Task PublishAsync(Guid conversationId, string kind, object payload, CancellationToken ct = default)
    {
        if (!_byConversation.TryGetValue(conversationId, out var bucket) || bucket.IsEmpty)
        {
            // No subscribers — nothing to do. The push notification path
            // (still wired) handles the offline case.
            return;
        }

        // Wrap as `{ kind, ...payloadFields }` so each frame is
        // self-describing. We serialize once and reuse the buffer.
        var envelope = new Dictionary<string, object?> { ["kind"] = kind };
        // Merge payload's properties via reflection-by-serialize-then-parse.
        // Acceptable cost for the small per-conversation fan-out.
        var payloadJson = JsonSerializer.Serialize(payload, JsonOptions);
        if (!string.IsNullOrEmpty(payloadJson) && payloadJson != "{}")
        {
            using var doc = JsonDocument.Parse(payloadJson);
            foreach (var prop in doc.RootElement.EnumerateObject())
            {
                envelope[prop.Name] = JsonSerializer.Deserialize<object>(prop.Value.GetRawText(), JsonOptions);
            }
        }
        var frameJson = JsonSerializer.Serialize(envelope, JsonOptions);
        var frameBytes = Encoding.UTF8.GetBytes(frameJson);

        foreach (var socket in bucket.Keys)
        {
            if (socket.State != WebSocketState.Open)
            {
                Unregister(socket);
                continue;
            }
            try
            {
                await socket.SendAsync(
                    new ArraySegment<byte>(frameBytes),
                    WebSocketMessageType.Text,
                    endOfMessage: true,
                    cancellationToken: ct);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex,
                    "realtime.publish failed; dropping socket conversation={ConversationId} kind={Kind}",
                    conversationId, kind);
                Unregister(socket);
            }
        }

        logger.LogInformation(
            "realtime.publish kind={Kind} conversation={ConversationId} subscribers={Count}",
            kind, conversationId, bucket.Count);
    }
}
