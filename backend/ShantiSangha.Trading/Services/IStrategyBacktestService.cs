using ShantiSangha.Trading.Contracts;

namespace ShantiSangha.Trading.Services;

public interface IStrategyBacktestService
{
    /// <summary>
    /// Return a coarse-envelope summary for the user's current rule
    /// constants. The actual simulator lives in `python/wisecat/strategy_sim.py`
    /// and runs offline — this method returns either the most recent
    /// pre-computed envelope or a transparent "run offline" placeholder
    /// with the exact CLI for the user's saved constants. Honest > flashy.
    /// </summary>
    Task<StrategyBacktestResultDto> RunAsync(Guid userId, CancellationToken ct = default);
}
