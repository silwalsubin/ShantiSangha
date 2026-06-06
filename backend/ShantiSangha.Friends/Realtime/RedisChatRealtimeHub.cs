using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using ShantiSangha.Shared.Interfaces;
using StackExchange.Redis;

namespace ShantiSangha.Friends.Realtime;

/// <summary>
/// Multi-instance chat realtime hub backed by Redis pub/sub.
///
/// WebSockets are inherently bound to a TCP connection, so each ECS task
/// owns its own subscriber registry. Cross-instance fan-out goes through
/// Redis: every <see cref="PublishAsync"/> publishes the JSON envelope to
/// `chat:realtime:{conversationId}`, and every instance is subscribed to
/// the wildcard `chat:realtime:*` so it can deliver to its own local
/// sockets when a peer instance broadcasts.
///
/// Self-echo is suppressed by tagging each envelope with an
/// <c>originInstanceId</c> (a process-lifetime Guid). The publishing
/// instance fans out to local sockets immediately for low latency, then
/// publishes to Redis for the rest; receiving instances skip messages
/// whose origin matches their own id so the publisher's local sockets
/// don't see the same frame twice.
///
/// If Redis is unreachable, <see cref="StackExchange.Redis"/> reconnects
/// in the background. During the gap, local fan-out keeps working —
/// only cross-instance delivery is lost. We log warnings but don't fail
/// the publish call: chat realtime is best-effort, the REST mutation is
/// the source of truth.
/// </summary>
// Also implements the Shared `IRealtimeBroadcaster` (its single PublishAsync
// matches the one below) so other modules (e.g. Chess) can broadcast without
// depending on Friends.
public class RedisChatRealtimeHub : IChatRealtimeHub, IRealtimeBroadcaster, IAsyncDisposable
{
    private record Subscriber(Guid UserId, Guid ConversationId, WebSocket Socket);

    // socket → subscriber, lets us unregister cheaply on disconnect.
    private readonly ConcurrentDictionary<WebSocket, Subscriber> _bySocket = new();

    // conversationId → set of sockets, lets us publish without scanning.
    // Inner ConcurrentDictionary used as a set (key = socket, value ignored).
    private readonly ConcurrentDictionary<Guid, ConcurrentDictionary<WebSocket, byte>> _byConversation = new();

    private readonly IConnectionMultiplexer _redis;
    private readonly ILogger<RedisChatRealtimeHub> _logger;
    private readonly Guid _instanceId = Guid.NewGuid();
    private readonly ISubscriber _subscriber;

    private const string ChannelPrefix = "chat:realtime:";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public RedisChatRealtimeHub(IConnectionMultiplexer redis, ILogger<RedisChatRealtimeHub> logger)
    {
        _redis = redis;
        _logger = logger;
        _subscriber = redis.GetSubscriber();

        // Pattern-subscribe once at startup. Multiple parallel deliveries
        // for different conversations are fine; the handler is small and
        // each call is async-safe.
        var pattern = RedisChannel.Pattern($"{ChannelPrefix}*");
        _subscriber.Subscribe(pattern).OnMessage(HandleRedisMessage);

        _logger.LogInformation(
            "realtime.hub redis-backed, instance={InstanceId}, pattern={Pattern}",
            _instanceId, ChannelPrefix + "*");
    }

    public void Register(Guid userId, Guid conversationId, WebSocket socket)
    {
        var subscriber = new Subscriber(userId, conversationId, socket);
        _bySocket[socket] = subscriber;
        var bucket = _byConversation.GetOrAdd(conversationId, _ => new ConcurrentDictionary<WebSocket, byte>());
        bucket[socket] = 0;
        _logger.LogDebug(
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
            _logger.LogDebug(
                "realtime.unsubscribe user={UserId} conversation={ConversationId}",
                subscriber.UserId, subscriber.ConversationId);
        }
    }

    public async Task PublishAsync(Guid conversationId, string kind, object payload, CancellationToken ct = default)
    {
        var frameJson = BuildEnvelope(conversationId, kind, payload);

        // 1) Local fan-out first — same-instance subscribers see the frame
        //    without paying the Redis round-trip.
        await FanOutLocallyAsync(conversationId, frameJson, kind, ct);

        // 2) Cross-instance fan-out via Redis pub/sub. Best-effort:
        //    transient connection failures are logged but don't fail the
        //    publish (REST is the source of truth).
        try
        {
            var channel = new RedisChannel($"{ChannelPrefix}{conversationId}", RedisChannel.PatternMode.Literal);
            await _subscriber.PublishAsync(channel, frameJson);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex,
                "realtime.publish redis broadcast failed kind={Kind} conversation={ConversationId}",
                kind, conversationId);
        }
    }

    private void HandleRedisMessage(ChannelMessage msg)
    {
        // The handler is invoked on a Redis library thread. Kick off the
        // async work without blocking the dispatcher.
        _ = Task.Run(async () => await HandleRedisMessageAsync(msg));
    }

    private async Task HandleRedisMessageAsync(ChannelMessage msg)
    {
        var json = (string?)msg.Message;
        if (string.IsNullOrEmpty(json)) return;

        // Drop self-originated messages: the publishing instance already
        // fanned out locally to its own sockets, so this is a duplicate.
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("originInstanceId", out var originEl)
                && Guid.TryParse(originEl.GetString(), out var origin)
                && origin == _instanceId)
            {
                return;
            }
        }
        catch (JsonException)
        {
            return;
        }

        // Channel name is `chat:realtime:{conversationId}` — pull the id
        // from the channel rather than the payload to avoid a second parse.
        var channelName = (string?)msg.Channel ?? string.Empty;
        if (!channelName.StartsWith(ChannelPrefix, StringComparison.Ordinal)) return;
        var convoIdStr = channelName.Substring(ChannelPrefix.Length);
        if (!Guid.TryParse(convoIdStr, out var conversationId)) return;

        await FanOutLocallyAsync(conversationId, json, "redis-relay", CancellationToken.None);
    }

    private async Task FanOutLocallyAsync(Guid conversationId, string frameJson, string kind, CancellationToken ct)
    {
        if (!_byConversation.TryGetValue(conversationId, out var bucket) || bucket.IsEmpty)
        {
            return;
        }

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
                _logger.LogWarning(ex,
                    "realtime.publish failed; dropping socket conversation={ConversationId} kind={Kind}",
                    conversationId, kind);
                Unregister(socket);
            }
        }

        _logger.LogInformation(
            "realtime.publish kind={Kind} conversation={ConversationId} subscribers={Count}",
            kind, conversationId, bucket.Count);
    }

    /// <summary>
    /// Wraps `kind` + `payload` + `originInstanceId` into a single JSON
    /// frame. The instance id is what lets receivers suppress self-echo;
    /// clients ignore unrecognized fields so it round-trips harmlessly.
    /// </summary>
    private string BuildEnvelope(Guid conversationId, string kind, object payload)
    {
        var envelope = new Dictionary<string, object?>
        {
            ["kind"] = kind,
            ["originInstanceId"] = _instanceId
        };

        var payloadJson = JsonSerializer.Serialize(payload, JsonOptions);
        if (!string.IsNullOrEmpty(payloadJson) && payloadJson != "{}")
        {
            using var doc = JsonDocument.Parse(payloadJson);
            foreach (var prop in doc.RootElement.EnumerateObject())
            {
                envelope[prop.Name] = JsonSerializer.Deserialize<object>(prop.Value.GetRawText(), JsonOptions);
            }
        }

        return JsonSerializer.Serialize(envelope, JsonOptions);
    }

    public async ValueTask DisposeAsync()
    {
        try
        {
            await _subscriber.UnsubscribeAllAsync();
        }
        catch
        {
            // Best-effort during shutdown; nothing else to do.
        }
    }
}
