using System.Net.WebSockets;

namespace ShantiSangha.Friends.Realtime;

/// <summary>
/// In-process registry of live WebSocket subscribers, keyed on
/// `conversationId`. The hub fans out events (`message_received`,
/// `message_edited`, `message_deleted`, `messages_read`, `typing`) to
/// every subscribed socket whose owning user is a member of the target
/// conversation.
///
/// V1 lives in the Friends module because friend chat is the only
/// caller. The interface stays generic on `conversationId` so a future
/// group-chat module can publish to the same hub without touching the
/// transport, and the membership question is delegated to
/// `IConversationMembershipService`.
/// </summary>
public interface IChatRealtimeHub
{
    /// <summary>Register a connected WebSocket as a subscriber to the
    /// given conversation. Caller is responsible for verifying
    /// membership BEFORE registering — the hub does not re-check.</summary>
    void Register(Guid userId, Guid conversationId, WebSocket socket);

    /// <summary>Remove a socket from the registry. Idempotent.</summary>
    void Unregister(WebSocket socket);

    /// <summary>Fan-out a JSON event payload to every socket that's
    /// currently subscribed to <paramref name="conversationId"/>. The
    /// payload is wrapped as `{ "kind": <kind>, ...fields }` so each
    /// frame is self-describing on the wire. Best-effort: a per-socket
    /// send failure is logged and the broken socket is removed, but
    /// PublishAsync as a whole always succeeds.</summary>
    Task PublishAsync(Guid conversationId, string kind, object payload, CancellationToken ct = default);
}
