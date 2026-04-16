using Microsoft.EntityFrameworkCore;
using ShantiSangha.Identity.Data;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Identity.Services;

public class ProfileQueryService(IdentityDbContext db) : IProfileQueryService
{
    public async Task<string?> GetDisplayNameAsync(Guid userId, CancellationToken ct = default)
    {
        return await db.Profiles
            .Where(p => p.UserId == userId)
            .Select(p => p.DisplayName)
            .FirstOrDefaultAsync(ct);
    }

    public async Task<UserBirthInfo> GetBirthInfoAsync(Guid userId, CancellationToken ct = default)
    {
        var profile = await db.Profiles
            .Where(p => p.UserId == userId)
            .Select(p => new { p.BirthDate, p.BirthTime, p.BirthPlace })
            .FirstOrDefaultAsync(ct);

        return new UserBirthInfo(profile?.BirthDate, profile?.BirthTime, profile?.BirthPlace);
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
