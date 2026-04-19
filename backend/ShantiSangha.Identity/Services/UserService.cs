using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Identity.Contracts;
using ShantiSangha.Identity.Data;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Identity.Services;

public class UserService(
    IdentityDbContext db,
    IChartReadingService chartReadingService,
    ILogger<UserService> logger) : IUserService
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
                user.Profile.OnboardingCompleted,
                user.Profile.BirthDate?.ToString("yyyy-MM-dd"),
                user.Profile.BirthTime,
                user.Profile.BirthPlace
            )
        );
    }

    public async Task<bool> UpdateMeAsync(Guid userId, UpdateMeRequest request, CancellationToken ct = default)
    {
        var user = await db.Users
            .Include(u => u.Profile)
            .FirstOrDefaultAsync(u => u.Id == userId, ct);

        if (user is null) return false;

        // Auto-create profile if it doesn't exist yet
        if (user.Profile is null)
        {
            user.Profile = new Models.Profile
            {
                Id = Guid.NewGuid(),
                UserId = user.Id,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };
            db.Profiles.Add(user.Profile);
        }

        var prevBirthDate = user.Profile.BirthDate;
        var prevBirthTime = user.Profile.BirthTime;
        var prevBirthPlace = user.Profile.BirthPlace;

        if (request.DisplayName is not null) user.Profile.DisplayName = request.DisplayName;
        if (request.Timezone is not null) user.Profile.Timezone = request.Timezone;
        if (request.ReminderHour is not null) user.Profile.ReminderHour = Math.Clamp(request.ReminderHour.Value, 0, 23);
        if (request.ClearReminderHour == true) user.Profile.ReminderHour = null;
        if (request.OnboardingCompleted is not null) user.Profile.OnboardingCompleted = request.OnboardingCompleted.Value;
        if (request.BirthDate is not null && DateOnly.TryParse(request.BirthDate, out var parsedBirthDate))
            user.Profile.BirthDate = parsedBirthDate;
        if (request.BirthTime is not null) user.Profile.BirthTime = request.BirthTime;
        if (request.BirthPlace is not null) user.Profile.BirthPlace = request.BirthPlace;
        if (request.ClearBirthDetails == true)
        {
            user.Profile.BirthDate = null;
            user.Profile.BirthTime = null;
            user.Profile.BirthPlace = null;
        }

        user.Profile.UpdatedAt = DateTime.UtcNow;
        user.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);

        var birthChanged =
            prevBirthDate != user.Profile.BirthDate ||
            prevBirthTime != user.Profile.BirthTime ||
            prevBirthPlace != user.Profile.BirthPlace;

        if (birthChanged)
        {
            try
            {
                await chartReadingService.InvalidateAsync(user.Id, ct);
            }
            catch (Exception ex)
            {
                // Invalidation failure is non-fatal — the stale-hash check in
                // ChartReadingService.GetAsync will still catch the change on
                // the next read. Log and move on.
                logger.LogWarning(ex,
                    "Failed to invalidate chart reading after birth details change for user {UserId}",
                    user.Id);
            }
        }

        return true;
    }
}
