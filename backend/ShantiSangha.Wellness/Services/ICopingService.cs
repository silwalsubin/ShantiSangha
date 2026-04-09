using ShantiSangha.Wellness.Contracts;

namespace ShantiSangha.Wellness.Services;

public interface ICopingService
{
    IReadOnlyList<ExerciseEntry> GetExercises();
    Task<CopingSessionResponse?> LogSessionAsync(Guid userId, string slug, LogSessionRequest request, CancellationToken ct = default);
    Task<List<CopingSessionListItem>> ListSessionsAsync(Guid userId, int page, int pageSize, CancellationToken ct = default);
}
