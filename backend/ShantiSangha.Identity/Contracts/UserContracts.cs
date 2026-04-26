namespace ShantiSangha.Identity.Contracts;

public record UpdateMeRequest(
    string? DisplayName,
    string? Timezone,
    int? ReminderHour,
    bool? NotifyOnFriendMessages,
    bool? OnboardingCompleted,
    bool? ClearReminderHour = null,
    string? BirthDate = null,
    string? BirthTime = null,
    string? BirthPlace = null,
    bool? ClearBirthDetails = null,
    string? Country = null,
    string? State = null,
    string? City = null,
    string? AvatarKey = null);

public record UserResponse(Guid Id, string Email, DateTime CreatedAt, ProfileResponse? Profile);

/// <summary>
/// Mirror of `Profile` for API consumers. `AvatarKey` is the raw S3 object
/// key (stable across reads); `AvatarUrl` is a short-lived presigned GET
/// URL (~1h TTL) generated at read time. Clients display the image via
/// AvatarUrl and round-trip AvatarKey only if the avatar upload flow set
/// it client-side (rare — usually the upload endpoint commits it for them).
/// </summary>
public record ProfileResponse(
    string? DisplayName,
    string? Timezone,
    int? ReminderHour,
    bool NotifyOnFriendMessages,
    bool OnboardingCompleted,
    string? BirthDate,
    string? BirthTime,
    string? BirthPlace,
    string? Country,
    string? State,
    string? City,
    string? AvatarKey,
    string? AvatarUrl);

public record AvatarUploadUrlRequest(string ContentType);

public record AvatarUploadUrlResponse(
    string ObjectKey,
    string UploadUrl,
    DateTime UploadUrlExpiresAt);
