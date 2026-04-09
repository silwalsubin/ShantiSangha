using ShantiSangha.Shared.Models;

namespace ShantiSangha.Shared.Interfaces;

public interface IMoodQueryService
{
    Task<MoodSummaryDto?> GetRecentMoodSummaryAsync(Guid userId, int days = 7, CancellationToken ct = default);
}
