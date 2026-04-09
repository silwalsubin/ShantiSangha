namespace ShantiSangha.Shared.Models;

public record GoalSummaryDto(
    string Title,
    string Type,
    int CurrentStreak,
    int Progress,
    string? DeeperWhy);
