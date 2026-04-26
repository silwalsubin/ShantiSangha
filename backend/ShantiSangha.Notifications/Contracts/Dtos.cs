namespace ShantiSangha.Notifications.Contracts;

/// <summary>
/// One row in the inbox list. `Payload` is the raw JSON string for the
/// type-specific shape (`friend_request_received` carries fromDisplayName +
/// requestId, etc.). The iOS layer decodes per-type since each producer
/// owns its own payload schema.
/// </summary>
public record NotificationResponse(
    Guid Id,
    string Type,
    string Payload,
    DateTime CreatedAt,
    DateTime? ViewedAt);

public record NotificationListResponse(
    int UnreadCount,
    List<NotificationResponse> Notifications);

public record UnreadCountResponse(int UnreadCount);
