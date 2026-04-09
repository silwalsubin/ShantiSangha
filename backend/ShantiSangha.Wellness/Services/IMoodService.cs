using ShantiSangha.Wellness.Contracts;

namespace ShantiSangha.Wellness.Services;

public interface IMoodService
{
    Task<MoodCheckinResponse> CreateCheckinAsync(Guid userId, CreateMoodCheckinRequest request, CancellationToken ct = default);
    Task<List<MoodCheckinListItem>> ListCheckinsAsync(Guid userId, DateTime? from, DateTime? to, int page, int pageSize, CancellationToken ct = default);
    Task<object> GetTrendsAsync(Guid userId, DateTime? from, DateTime? to, CancellationToken ct = default);
}
