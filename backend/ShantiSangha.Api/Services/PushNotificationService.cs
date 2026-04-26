using FirebaseAdmin.Messaging;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Identity.Data;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Api.Services;

public class PushNotificationService(
    IdentityDbContext db,
    ILogger<PushNotificationService> logger) : IPushNotificationService
{
    public async Task SendSilentPushAsync(Guid userId, Dictionary<string, string> data, CancellationToken ct = default)
    {
        var tokens = await db.DeviceTokens
            .Where(d => d.UserId == userId)
            .Select(d => new { d.Id, d.Token })
            .ToListAsync(ct);

        if (tokens.Count == 0)
        {
            logger.LogDebug("No device tokens for user {UserId}, skipping push", userId);
            return;
        }

        foreach (var device in tokens)
        {
            try
            {
                var message = new Message
                {
                    Token = device.Token,
                    Data = data,
                    Apns = new ApnsConfig
                    {
                        Headers = new Dictionary<string, string>
                        {
                            ["apns-push-type"] = "background",
                            ["apns-priority"] = "5"
                        },
                        Aps = new Aps { ContentAvailable = true }
                    }
                };

                await FirebaseMessaging.DefaultInstance.SendAsync(message, ct);
                logger.LogInformation("Silent push sent to user {UserId} device {DeviceId} type={Type}",
                    userId, device.Id, data.GetValueOrDefault("type"));
            }
            catch (FirebaseMessagingException ex) when (ex.MessagingErrorCode == MessagingErrorCode.Unregistered)
            {
                // Token is stale — remove it
                logger.LogWarning("Removing stale device token {DeviceId} for user {UserId}", device.Id, userId);
                var stale = await db.DeviceTokens.FindAsync([device.Id], ct);
                if (stale is not null)
                {
                    db.DeviceTokens.Remove(stale);
                    await db.SaveChangesAsync(ct);
                }
            }
            catch (Exception ex)
            {
                // Push is best-effort — log but don't fail the calling job
                logger.LogError(ex, "Failed to send push to device {DeviceId} for user {UserId}", device.Id, userId);
            }
        }
    }

    public async Task SendAlertPushAsync(
        Guid userId,
        string title,
        string body,
        Dictionary<string, string>? data = null,
        int? badge = null,
        CancellationToken ct = default)
    {
        var tokens = await db.DeviceTokens
            .Where(d => d.UserId == userId)
            .Select(d => new { d.Id, d.Token })
            .ToListAsync(ct);

        if (tokens.Count == 0)
        {
            logger.LogDebug("No device tokens for user {UserId}, skipping alert push", userId);
            return;
        }

        foreach (var device in tokens)
        {
            try
            {
                var message = new Message
                {
                    Token = device.Token,
                    Notification = new Notification { Title = title, Body = body },
                    Data = data ?? new Dictionary<string, string>(),
                    Apns = new ApnsConfig
                    {
                        Headers = new Dictionary<string, string>
                        {
                            ["apns-push-type"] = "alert",
                            ["apns-priority"] = "10"
                        },
                        Aps = new Aps
                        {
                            Alert = new ApsAlert { Title = title, Body = body },
                            Sound = "default",
                            // null leaves the home-screen badge alone; an
                            // integer (including 0) sets it to that exact
                            // count. Callers pass the recipient's current
                            // inbox unread count to keep the icon in sync
                            // with the in-app bell badge.
                            Badge = badge
                        }
                    }
                };

                await FirebaseMessaging.DefaultInstance.SendAsync(message, ct);
                logger.LogInformation("Alert push sent to user {UserId} device {DeviceId} type={Type} badge={Badge}",
                    userId, device.Id, data?.GetValueOrDefault("type") ?? "none", badge?.ToString() ?? "none");
            }
            catch (FirebaseMessagingException ex) when (ex.MessagingErrorCode == MessagingErrorCode.Unregistered)
            {
                logger.LogWarning("Removing stale device token {DeviceId} for user {UserId}", device.Id, userId);
                var stale = await db.DeviceTokens.FindAsync([device.Id], ct);
                if (stale is not null)
                {
                    db.DeviceTokens.Remove(stale);
                    await db.SaveChangesAsync(ct);
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Failed to send alert push to device {DeviceId} for user {UserId}", device.Id, userId);
            }
        }
    }
}
