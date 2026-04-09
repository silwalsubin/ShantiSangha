namespace ShantiSangha.Shared.Models;

public record MoodSummaryDto(
    double AverageScore,
    int CheckInCount,
    string Trend);
