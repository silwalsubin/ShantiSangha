namespace ShantiSangha.Notifications.Models;

/// <summary>
/// One in-app notification for one recipient. Generic by design — the
/// `Type` field discriminates between event kinds (friend_request_received,
/// friend_request_accepted, future: friend_message, milestone, system) and
/// `PayloadJson` carries the type-specific data the iOS layer needs to
/// render the row (sender name, friend request id, friendship id, etc.).
///
/// Read state: `ViewedAt` is set once when the user opens the inbox —
/// that drives the bell-icon badge count (count rows where `ViewedAt is null`).
/// We don't track per-row taps; a row stays in the inbox until it ages out
/// (future cleanup job) regardless of viewing status.
/// </summary>
public class AppNotification
{
    public Guid Id { get; set; }

    /// <summary>The user who receives this notification.</summary>
    public Guid RecipientUserId { get; set; }

    /// <summary>Stable string discriminator. Examples:
    ///   - "friend_request_received"
    ///   - "friend_request_accepted"
    /// New types are added by callers; this column is just a string so we
    /// don't need a schema migration to introduce a new type.</summary>
    public string Type { get; set; } = string.Empty;

    /// <summary>JSON-encoded payload specific to the type. Kept loose so
    /// each producer module owns its own shape; iOS decodes per-type.
    /// Example for friend_request_received:
    ///   { "requestId": "...", "fromUserId": "...", "fromDisplayName": "..." }
    /// </summary>
    public string PayloadJson { get; set; } = "{}";

    public DateTime CreatedAt { get; set; }

    /// <summary>Set when the user first opens the inbox containing this
    /// notification. Null until then. Drives the unread-count badge.</summary>
    public DateTime? ViewedAt { get; set; }
}
