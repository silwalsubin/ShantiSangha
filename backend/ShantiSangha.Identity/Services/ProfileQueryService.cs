using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Identity.Data;
using ShantiSangha.Identity.Storage;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Identity.Services;

public class ProfileQueryService(
    IdentityDbContext db,
    AvatarStorage avatarStorage,
    ILogger<ProfileQueryService> logger) : IProfileQueryService
{
    private static readonly TimeSpan AvatarUrlLifetime = TimeSpan.FromHours(1);

    public async Task<string?> GetDisplayNameAsync(Guid userId, CancellationToken ct = default)
    {
        return await db.Profiles
            .Where(p => p.UserId == userId)
            .Select(p => p.DisplayName)
            .FirstOrDefaultAsync(ct);
    }

    public async Task<UserAvatarInfo> GetAvatarInfoAsync(Guid userId, CancellationToken ct = default)
    {
        var key = await db.Profiles
            .Where(p => p.UserId == userId)
            .Select(p => p.AvatarKey)
            .FirstOrDefaultAsync(ct);

        if (string.IsNullOrEmpty(key))
        {
            return new UserAvatarInfo(null, null);
        }

        try
        {
            var url = await avatarStorage.GetPresignedDownloadUrlAsync(key, AvatarUrlLifetime);
            return new UserAvatarInfo(key, url);
        }
        catch (Exception ex)
        {
            // Per-row presign failure is non-fatal — return the key so a
            // smarter caller could retry, and log so it shows up in
            // CloudWatch if it ever happens at scale.
            logger.LogWarning(ex, "Failed to presign avatar URL for user {UserId}", userId);
            return new UserAvatarInfo(key, null);
        }
    }

    public async Task<UserBirthInfo> GetBirthInfoAsync(Guid userId, CancellationToken ct = default)
    {
        var profile = await db.Profiles
            .Where(p => p.UserId == userId)
            .Select(p => new { p.BirthDate, p.BirthTime, p.BirthPlace })
            .FirstOrDefaultAsync(ct);

        return new UserBirthInfo(profile?.BirthDate, profile?.BirthTime, profile?.BirthPlace);
    }

    public async Task<bool> GetFriendMessageNotificationsEnabledAsync(Guid userId, CancellationToken ct = default)
    {
        var enabled = await db.Profiles
            .Where(p => p.UserId == userId)
            .Select(p => (bool?)p.NotifyOnFriendMessages)
            .FirstOrDefaultAsync(ct);

        return enabled ?? true;
    }

    public async Task<IReadOnlyList<UserTimezoneInfo>> GetAllUserTimezonesAsync(CancellationToken ct = default)
    {
        return await db.Profiles
            .Select(p => new UserTimezoneInfo(p.UserId, p.Timezone))
            .ToListAsync(ct);
    }

    public async Task<IReadOnlyList<UserReminderInfo>> GetUsersWithRemindersAsync(CancellationToken ct = default)
    {
        return await db.Profiles
            .Where(p => p.ReminderHour != null)
            .Select(p => new UserReminderInfo(p.UserId, p.Timezone, p.ReminderHour))
            .ToListAsync(ct);
    }
}
