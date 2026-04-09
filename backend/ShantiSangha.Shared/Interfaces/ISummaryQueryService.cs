namespace ShantiSangha.Shared.Interfaces;

public interface ISummaryQueryService
{
    Task<IReadOnlyList<string>> GetRecentSummariesAsync(Guid userId, int count = 3, CancellationToken ct = default);
    Task<IReadOnlyList<string>> GetRecentJournalSummariesAsync(Guid userId, int count = 3, CancellationToken ct = default);
}
