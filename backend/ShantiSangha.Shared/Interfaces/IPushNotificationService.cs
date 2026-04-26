namespace ShantiSangha.Shared.Interfaces;

public interface IPushNotificationService
{
    Task SendSilentPushAsync(Guid userId, Dictionary<string, string> data, CancellationToken ct = default);

    /// <summary>
    /// Sends a visible push notification with a title and body shown on the user's
    /// lock screen / notification center. Optional data payload for deep linking.
    /// `badge` sets the APNs `aps.badge` field — pass the recipient's current
    /// inbox unread count to update the home-screen app icon, or leave null to
    /// leave the icon unchanged. Pass 0 explicitly to clear the icon.
    /// </summary>
    Task SendAlertPushAsync(
        Guid userId,
        string title,
        string body,
        Dictionary<string, string>? data = null,
        int? badge = null,
        CancellationToken ct = default);
}
