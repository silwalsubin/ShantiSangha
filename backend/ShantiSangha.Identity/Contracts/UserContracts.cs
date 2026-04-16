namespace ShantiSangha.Identity.Contracts;

public record UpdateMeRequest(
    string? DisplayName,
    string? Timezone,
    int? ReminderHour,
    bool? OnboardingCompleted,
    bool? ClearReminderHour = null,
    DateOnly? BirthDate = null,
    string? BirthTime = null,
    string? BirthPlace = null,
    bool? ClearBirthDetails = null);

public record UserResponse(Guid Id, string Email, DateTime CreatedAt, ProfileResponse? Profile);

public record ProfileResponse(
    string? DisplayName,
    string? Timezone,
    int? ReminderHour,
    bool OnboardingCompleted,
    DateOnly? BirthDate,
    string? BirthTime,
    string? BirthPlace);
