using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Shared.Jobs;

public class SendPushNotificationJob(IPushNotificationService pushService)
{
    public async Task RunAsync(Guid userId, string type)
    {
        await pushService.SendSilentPushAsync(userId, new Dictionary<string, string> { ["type"] = type });
    }
}
