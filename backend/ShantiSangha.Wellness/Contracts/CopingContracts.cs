namespace ShantiSangha.Wellness.Contracts;

public record ExerciseEntry(string Slug, string Name, string Description, string Category, int DefaultDurationSeconds);

public record LogSessionRequest(int DurationSeconds, string? Notes);

public record CopingSessionResponse(Guid Id, string ExerciseSlug, int DurationSeconds, DateTime CompletedAt);

public record CopingSessionListItem(Guid Id, string ExerciseSlug, int DurationSeconds, string? Notes, DateTime CompletedAt);
