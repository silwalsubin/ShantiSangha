namespace ShantiSangha.Wellness.Contracts;

public record CreateMoodCheckinRequest(int Score, string? Notes);

public record MoodCheckinResponse(Guid Id, int Score, DateTime CreatedAt);

public record MoodCheckinListItem(Guid Id, int Score, string? Notes, DateTime CreatedAt);

public record MoodTrendsResponse(
    double? Average,
    int? Highest,
    int? Lowest,
    string? Trend,
    int? TotalCheckins,
    object[] DailyAverages);

public record DailyAverageItem(DateTime Date, double Average, int Count);
