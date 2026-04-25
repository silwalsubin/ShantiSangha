namespace ShantiSangha.Shared.Interfaces;

public record UserTimezoneInfo(Guid UserId, string? Timezone);

public record UserReminderInfo(Guid UserId, string? Timezone, int? ReminderHour);

public record UserBirthInfo(DateOnly? BirthDate, string? BirthTime, string? BirthPlace);

/// <summary>
/// What a consumer needs to render another user's avatar: the stable S3 key
/// for round-tripping, plus a short-lived presigned GET URL for displaying
/// the image. AvatarUrl is null when the user has no avatar uploaded or
/// when the URL presign step failed (presign failure is non-fatal — the
/// row still flows through with a null URL and the iOS layer falls back to
/// the default-icon circle).
/// </summary>
public record UserAvatarInfo(string? AvatarKey, string? AvatarUrl);

public interface IProfileQueryService
{
    Task<string?> GetDisplayNameAsync(Guid userId, CancellationToken ct = default);

    /// <summary>
    /// Returns the user's avatar key + a freshly-presigned download URL.
    /// Used by the Friends module to surface friend avatars without
    /// coupling to Identity's AvatarStorage directly. Both fields are
    /// nullable — null AvatarKey means "no avatar set", null AvatarUrl
    /// means "presign failed but we still know the key".
    /// </summary>
    Task<UserAvatarInfo> GetAvatarInfoAsync(Guid userId, CancellationToken ct = default);

    /// <summary>
    /// Returns birth details for Jyotish context computation.
    /// Returns null fields if the user hasn't provided birth data.
    /// </summary>
    Task<UserBirthInfo> GetBirthInfoAsync(Guid userId, CancellationToken ct = default);

    /// <summary>
    /// Returns all user profiles with their timezone (may be null).
    /// Used by scheduled jobs that need to act per-user-local-time.
    /// </summary>
    Task<IReadOnlyList<UserTimezoneInfo>> GetAllUserTimezonesAsync(CancellationToken ct = default);

    /// <summary>
    /// Returns all user profiles that have a reminder hour set (non-null),
    /// along with their timezone. Used by the morning reflection push job.
    /// </summary>
    Task<IReadOnlyList<UserReminderInfo>> GetUsersWithRemindersAsync(CancellationToken ct = default);
}
