using ShantiSangha.Shared.Models;

namespace ShantiSangha.Shared.Interfaces;

public interface IJournalSearchService
{
    Task<IReadOnlyList<SemanticSearchResultDto>> SearchAsync(Guid userId, string query, int topK = 5, CancellationToken ct = default);
}
