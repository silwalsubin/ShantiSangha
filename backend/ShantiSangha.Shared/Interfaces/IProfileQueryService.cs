namespace ShantiSangha.Shared.Interfaces;

public record UserTimezoneInfo(Guid UserId, string? Timezone);

public record UserReminderInfo(Guid UserId, string? Timezone, int? ReminderHour);

public record UserBirthInfo(DateOnly? BirthDate, string? BirthTime, string? BirthPlace);

public interface IProfileQueryService
{
    Task<string?> GetDisplayNameAsync(Guid userId, CancellationToken ct = default);

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
