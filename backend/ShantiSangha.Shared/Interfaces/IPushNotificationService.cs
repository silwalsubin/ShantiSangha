namespace ShantiSangha.Shared.Interfaces;

public interface IPushNotificationService
{
    Task SendSilentPushAsync(Guid userId, Dictionary<string, string> data, CancellationToken ct = default);

    /// <summary>
    /// Sends a visible push notification with a title and body shown on the user's
    /// lock screen / notification center. Optional data payload for deep linking.
    /// </summary>
    Task SendAlertPushAsync(Guid userId, string title, string body, Dictionary<string, string>? data = null, CancellationToken ct = default);
}
