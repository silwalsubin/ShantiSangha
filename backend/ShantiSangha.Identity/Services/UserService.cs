using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Identity.Contracts;
using ShantiSangha.Identity.Data;
using ShantiSangha.Identity.Storage;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Identity.Services;

public class UserService(
    IdentityDbContext db,
    IChartReadingService chartReadingService,
    AvatarStorage avatarStorage,
    ILogger<UserService> logger) : IUserService
{
    private static readonly TimeSpan AvatarUrlLifetime = TimeSpan.FromHours(1);

    public async Task<UserResponse?> GetMeAsync(Guid userId, CancellationToken ct = default)
    {
        var user = await db.Users
            .Include(u => u.Profile)
            .FirstOrDefaultAsync(u => u.Id == userId, ct);

        if (user is null) return null;

        // Generate a fresh presigned download URL for the avatar at read
        // time so the URL is always valid for the lifetime of one /me
        // refresh on the client. Failure here is non-fatal — we'd rather
        // return the rest of the profile with no avatar URL than 500 the
        // whole request.
        string? avatarUrl = null;
        if (user.Profile?.AvatarKey is { Length: > 0 } key)
        {
            try
            {
                avatarUrl = await avatarStorage.GetPresignedDownloadUrlAsync(key, AvatarUrlLifetime);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to presign avatar URL for user {UserId}", userId);
            }
        }

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
                user.Profile.BirthPlace,
                user.Profile.Country,
                user.Profile.State,
                user.Profile.City,
                user.Profile.AvatarKey,
                avatarUrl
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

        if (request.Country is not null) user.Profile.Country = request.Country;
        if (request.State is not null) user.Profile.State = request.State;
        if (request.City is not null) user.Profile.City = request.City;

        // Avatar key is only set via the upload-commit flow. When a new key
        // arrives and replaces a previous one, eagerly delete the old object
        // so we don't accumulate orphans across re-uploads.
        if (request.AvatarKey is not null && request.AvatarKey != user.Profile.AvatarKey)
        {
            var oldKey = user.Profile.AvatarKey;
            user.Profile.AvatarKey = string.IsNullOrWhiteSpace(request.AvatarKey) ? null : request.AvatarKey;
            if (!string.IsNullOrWhiteSpace(oldKey))
            {
                _ = avatarStorage.DeleteAsync(oldKey);
            }
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

    private static readonly HashSet<string> AllowedAvatarTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg", "image/jpg", "image/png", "image/heic", "image/webp"
    };

    private static readonly TimeSpan AvatarUploadUrlLifetime = TimeSpan.FromMinutes(15);

    public async Task<AvatarUploadUrlResponse?> CreateAvatarUploadUrlAsync(
        Guid userId, AvatarUploadUrlRequest request, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(request.ContentType) ||
            !AllowedAvatarTypes.Contains(request.ContentType))
        {
            return null;
        }

        var userExists = await db.Users.AnyAsync(u => u.Id == userId, ct);
        if (!userExists) return null;

        var key = avatarStorage.BuildKey(userId, request.ContentType);
        var url = await avatarStorage.GetPresignedUploadUrlAsync(
            key, request.ContentType, AvatarUploadUrlLifetime);

        return new AvatarUploadUrlResponse(
            ObjectKey: key,
            UploadUrl: url,
            UploadUrlExpiresAt: DateTime.UtcNow.Add(AvatarUploadUrlLifetime));
    }
}
