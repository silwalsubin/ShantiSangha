using ShantiSangha.Shared.Models;

namespace ShantiSangha.Shared.Interfaces;

public interface IGoalQueryService
{
    Task<IReadOnlyList<GoalSummaryDto>> GetActiveGoalsForContextAsync(Guid userId, DateOnly? localDate = null, CancellationToken ct = default);
}
