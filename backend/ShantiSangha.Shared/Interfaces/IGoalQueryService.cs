using ShantiSangha.Shared.Models;

namespace ShantiSangha.Shared.Interfaces;

public interface IGoalQueryService
{
    Task<IReadOnlyList<GoalSummaryDto>> GetActiveGoalsForContextAsync(Guid userId, CancellationToken ct = default);
}
