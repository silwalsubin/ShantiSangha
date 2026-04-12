namespace ShantiSangha.Shared.Interfaces;

public interface IPushNotificationService
{
    Task SendSilentPushAsync(Guid userId, Dictionary<string, string> data, CancellationToken ct = default);
}
