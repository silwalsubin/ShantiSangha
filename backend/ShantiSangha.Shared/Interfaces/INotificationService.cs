namespace ShantiSangha.Shared.Interfaces;

/// <summary>
/// Cross-module entry point for enqueueing in-app notifications. Lives in
/// Shared so any module (Friends, Chat, Wellness, future ones) can fire a
/// notification at a recipient without depending on the Notifications
/// module directly. The implementation in Notifications writes to its own
/// DbContext and is the only place that knows the AppNotification table
/// shape — callers just hand over `(recipient, type, payload)`.
/// </summary>
public interface INotificationService
{
    /// <summary>
    /// Persist a notification for the given recipient. `type` is a stable
    /// string discriminator (e.g. "friend_request_received"); `payload` is
    /// any JSON-serializable object the iOS layer needs to render the row.
    /// Fire-and-forget at the caller's discretion — the method returns the
    /// new notification id but failure to persist throws so the caller can
    /// log if it cares.
    /// </summary>
    Task<Guid> EnqueueAsync(
        Guid recipientUserId,
        string type,
        object? payload = null,
        CancellationToken ct = default);

    /// <summary>
    /// Count of unviewed notifications for a user. Used by cross-module
    /// callers (e.g. FriendRequestsService) to compute the APNs badge
    /// value to send alongside a notification-shaped push, keeping the
    /// home-screen icon and the in-app bell badge in sync. Pattern: call
    /// AFTER `EnqueueAsync` so the new row is included in the count.
    /// </summary>
    Task<int> GetUnreadCountAsync(Guid userId, CancellationToken ct = default);
}
