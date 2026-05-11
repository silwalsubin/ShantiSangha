using ShantiSangha.Shared.Models;

namespace ShantiSangha.Shared.Interfaces;

public interface IPracticeQueryService
{
    Task<IReadOnlyList<PracticeSummaryDto>> GetActivePracticesForContextAsync(Guid userId, DateOnly? localDate = null, CancellationToken ct = default);
}
