using Microsoft.EntityFrameworkCore;
using ShantiSangha.Identity.Contracts;
using ShantiSangha.Identity.Data;

namespace ShantiSangha.Identity.Services;

public class UserService(IdentityDbContext db) : IUserService
{
    public async Task<UserResponse?> GetMeAsync(Guid userId, CancellationToken ct = default)
    {
        var user = await db.Users
            .Include(u => u.Profile)
            .FirstOrDefaultAsync(u => u.Id == userId, ct);

        if (user is null) return null;

        return new UserResponse(
            user.Id,
            user.Email,
            user.CreatedAt,
            user.Profile is null ? null : new ProfileResponse(
                user.Profile.DisplayName,
                user.Profile.Timezone,
                user.Profile.ReminderHour,
                user.Profile.OnboardingCompleted
            )
        );
    }

    public async Task<bool> UpdateMeAsync(Guid userId, UpdateMeRequest request, CancellationToken ct = default)
    {
        var user = await db.Users
            .Include(u => u.Profile)
            .FirstOrDefaultAsync(u => u.Id == userId, ct);

        if (user is null) return false;
        if (user.Profile is null) return false;

        if (request.DisplayName is not null) user.Profile.DisplayName = request.DisplayName;
        if (request.Timezone is not null) user.Profile.Timezone = request.Timezone;
        if (request.ReminderHour is not null) user.Profile.ReminderHour = Math.Clamp(request.ReminderHour.Value, 0, 23);
        if (request.ClearReminderHour == true) user.Profile.ReminderHour = null;
        if (request.OnboardingCompleted is not null) user.Profile.OnboardingCompleted = request.OnboardingCompleted.Value;

        user.Profile.UpdatedAt = DateTime.UtcNow;
        user.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);

        return true;
    }
}
