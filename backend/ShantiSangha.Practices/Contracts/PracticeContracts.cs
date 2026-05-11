using ShantiSangha.Practices.Models;

namespace ShantiSangha.Practices.Contracts;

// ── Requests ────────────────────────────────────────────────────────────

public record CreatePracticeRequest(
    string Title,
    PracticeFrequency? Frequency = null,
    int? FrequencyTarget = null,
    string? DeeperWhy = null);

public record UpdatePracticeRequest(
    string? Title,
    bool? Archived,
    string? DeeperWhy = null);

public record CheckInRequest(bool Completed, string? Note, string? Date = null);

// ── Responses ───────────────────────────────────────────────────────────

public record PracticeCreatedResponse(
    Guid Id,
    string Title,
    string? Frequency,
    int? FrequencyTarget,
    string? DeeperWhy,
    DateTime CreatedAt);

public record PracticeResponse(
    Guid Id,
    string Title,
    string? Frequency,
    int? FrequencyTarget,
    DateTime CreatedAt,
    int CurrentStreak,
    int LongestStreak,
    CheckInResponse? CheckIn = null);

public record PracticeDetailResponse(
    Guid Id,
    string Title,
    string? Frequency,
    int? FrequencyTarget,
    string? DeeperWhy,
    DateTime CreatedAt,
    int CurrentStreak,
    int LongestStreak);

public record TodayPracticeResponse(
    Guid Id,
    string Title,
    int CurrentStreak,
    int LongestStreak,
    CheckInResponse? CheckIn);

public record CheckInResponse(bool Completed, string? Note);

public record CheckInResult(Guid Id, DateOnly Date, bool Completed, string? Note);

public record CheckInListItem(Guid Id, string Date, bool Completed, string? Note);

public record PracticeActivityResponse(Guid Id, string Action, string? Detail, DateTime CreatedAt);

public record JourneyPractice(
    Guid Id,
    string Title,
    int DaysCompleted,
    int TotalDays,
    int CurrentStreak,
    int LongestStreak,
    List<JourneyDay> Days);

public record JourneyDay(string Date, bool Completed);

public record JourneySummary(
    int PracticesCompleted,
    int PracticesPossible,
    double CompletionRate);

public record JourneyResponse(
    string From,
    string To,
    int TotalDays,
    List<JourneyPractice> Practices,
    JourneySummary Summary);

public record JourneyReflectionResponse(string? Reflection);
