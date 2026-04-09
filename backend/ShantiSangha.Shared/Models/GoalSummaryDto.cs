namespace ShantiSangha.Shared.Models;

public record GoalSummaryDto(
    string Title,
    string Type,
    int CurrentStreak,
    int LongestStreak,
    bool? CheckedInToday,
    int? DaysRemaining,
    bool IsCompleted,
    int Progress,
    string? DeeperWhy);
