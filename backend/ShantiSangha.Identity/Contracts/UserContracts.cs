namespace ShantiSangha.Identity.Contracts;

public record UpdateMeRequest(string? DisplayName, string? Timezone, int? ReminderHour, bool? OnboardingCompleted, bool? ClearReminderHour = null);

public record UserResponse(Guid Id, string Email, DateTime CreatedAt, ProfileResponse? Profile);

public record ProfileResponse(string? DisplayName, string? Timezone, int? ReminderHour, bool OnboardingCompleted);
