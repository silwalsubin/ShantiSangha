using ShantiSangha.Goals.Models;

namespace ShantiSangha.Goals.Contracts;

// ── Requests ────────────────────────────────────────────────────────────

public record CreateGoalRequest(
    string Title,
    GoalType Type = GoalType.Recurring,
    GoalFrequency? Frequency = null,
    int? FrequencyTarget = null,
    string? TargetDate = null,
    string? DeeperWhy = null);

public record UpdateGoalRequest(
    string? Title,
    bool? Archived,
    bool? Completed,
    string? DeeperWhy = null,
    int? Progress = null,
    string? TargetDate = null);

public record CheckInRequest(bool Completed, string? Note, string? Date = null);

// ── Responses ───────────────────────────────────────────────────────────

public record GoalCreatedResponse(
    Guid Id,
    string Title,
    string Type,
    string? Frequency,
    int? FrequencyTarget,
    DateOnly? TargetDate,
    string? DeeperWhy,
    DateTime CreatedAt);

public record RecurringGoalResponse(
    Guid Id,
    string Title,
    string Type,
    string? Frequency,
    int? FrequencyTarget,
    DateTime CreatedAt,
    int CurrentStreak,
    int LongestStreak,
    CheckInResponse? CheckIn = null);

public record OneTimeGoalResponse(
    Guid Id,
    string Title,
    string Type,
    DateOnly? TargetDate,
    int Progress,
    DateTime? CompletedAt,
    DateTime CreatedAt,
    int? DaysRemaining,
    int NoteCount,
    CheckInResponse? CheckIn = null);

public record RecurringGoalDetailResponse(
    Guid Id,
    string Title,
    string Type,
    string? Frequency,
    int? FrequencyTarget,
    string? DeeperWhy,
    DateTime CreatedAt,
    int CurrentStreak,
    int LongestStreak,
    string? AiNudge);

public record OneTimeGoalDetailResponse(
    Guid Id,
    string Title,
    string Type,
    DateOnly? TargetDate,
    string? DeeperWhy,
    int Progress,
    DateTime? CompletedAt,
    DateTime CreatedAt,
    int? DaysRemaining,
    int NoteCount,
    string? AiNudge);

public record TodayGoalResponse(
    Guid Id,
    string Title,
    int CurrentStreak,
    int LongestStreak,
    CheckInResponse? CheckIn);

public record CheckInResponse(bool Completed, string? Note);

public record CheckInResult(Guid Id, DateOnly Date, bool Completed, string? Note);

public record CheckInListItem(Guid Id, string Date, bool Completed, string? Note);

public record GoalActivityResponse(Guid Id, string Action, string? Detail, DateTime CreatedAt);

public record NudgeResult(string? Nudge);

public record JourneyPractice(
    Guid Id,
    string Title,
    int DaysCompleted,
    int TotalDays,
    int CurrentStreak,
    int LongestStreak,
    List<JourneyDay> Days);

public record JourneyDay(string Date, bool Completed);

public record JourneyCompletedCommitment(Guid Id, string Title, DateTime? CompletedAt);

public record JourneySummary(
    int PracticesCompleted,
    int PracticesPossible,
    double CompletionRate,
    int CommitmentsFinished);

public record JourneyResponse(
    string From,
    string To,
    int TotalDays,
    List<JourneyPractice> Practices,
    List<JourneyCompletedCommitment> CompletedCommitments,
    JourneySummary Summary);

public record JourneyReflectionResponse(string? Reflection);
