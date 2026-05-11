namespace ShantiSangha.Shared.Models;

public record PracticeSummaryDto(
    string Title,
    int CurrentStreak,
    int LongestStreak,
    bool CheckedInToday,
    string? DeeperWhy);
