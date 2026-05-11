using System.Globalization;
using ShantiSangha.Trading.Contracts;

namespace ShantiSangha.Trading.Services;

/// <summary>
/// Returns an honest "use strategy_sim.py" envelope. We don't run the
/// simulator inside the API request path — it pulls multi-year yfinance
/// histories, scores every trading day with the GBM, and takes minutes.
/// Doing that synchronously per click would burn Lambda budget AND lie
/// about precision. The right surface is: show the user the exact CLI
/// they can run locally, with their saved constants baked in.
///
/// The pre-computed envelope numbers below come from the 2026-05-10
/// basket backtest captured in the Trading-strategy-rules memory. If
/// they ever go stale, rerun and update the constants here.
/// </summary>
public class StrategyBacktestService(IStrategySettingsService strategySettings) : IStrategyBacktestService
{
    public async Task<StrategyBacktestResultDto> RunAsync(Guid userId, CancellationToken ct = default)
    {
        var s = await strategySettings.GetOrCreateAsync(userId, ct);

        // The 2026-05-10 basket backtest envelope for the Mode D defaults.
        const double baselineReturn = 0.082;
        const double baselineDrawdown = -0.18;
        const double baselineWinRate = 0.55;
        const double baselineSharpe = 0.65;

        // First-order envelope adjustments. Real numbers require a real
        // backtest — these are intentionally conservative heuristics so the
        // UI surfaces *direction* without pretending to be precise:
        //   - Wider stops bleed less on chop but cost more per loser.
        //   - Higher entry threshold trades less, captures less upside.
        //   - Lower take-profit caps winners more aggressively.
        var stopPenalty = ((double)s.StopLossPct - 0.07) * 0.8;        // wider stop → small return drag
        var tpDrag = (0.10 - (double)s.TakeProfitPct) * 0.4;            // tighter TP → real drag
        var threshDrag = ((double)s.EntryThresholdPBuy - 0.60) * 0.35;  // pickier entries → less in-market
        var ret = baselineReturn - stopPenalty - tpDrag - threshDrag;

        var ddBuffer = ((double)s.StopLossPct - 0.07) * 1.2;            // wider stop → deeper DD
        var dd = baselineDrawdown - ddBuffer;

        var notes =
            "Envelope estimate based on the 2026-05-10 basket backtest. " +
            "Run `python -m wisecat.strategy_sim " +
            $"--stop-loss {((double)s.StopLossPct):F2} " +
            $"--entry-threshold {((double)s.EntryThresholdPBuy).ToString("F2", CultureInfo.InvariantCulture)} " +
            $"--horizon {s.EntryHorizon} " +
            $"--cooldown-days {s.CooldownDays} " +
            $"--take-profit {((double)s.TakeProfitPct).ToString("F2", CultureInfo.InvariantCulture)}` " +
            "for the precise pooled-regime result before changing the saved rules.";

        return new StrategyBacktestResultDto(
            Window: "2014–2024 pooled (3 regimes)",
            AnnualizedReturnPct: Math.Round(ret, 4),
            MaxDrawdownPct: Math.Round(dd, 4),
            Trades: 0,
            WinRatePct: baselineWinRate,
            SharpeApprox: baselineSharpe,
            Notes: notes
        );
    }
}
