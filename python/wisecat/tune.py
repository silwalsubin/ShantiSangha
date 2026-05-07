"""Per-horizon weight tuning report.

Runs the technical-only backtest for all three horizons (1W / 1M / 1Y) on
one history pull, then prints a single table comparing each strategy's
current weight against its hit rate at that horizon's native forward
window:

    1W ensemble × 5-day forward return
    1M ensemble × 21-day forward return
    1Y ensemble × 252-day forward return

These are the diagonal cells of the 3 × 3 (horizon × forward-window) grid
— the cells that justify each per-horizon weight vector. Off-diagonal
cells are sanity checks (and you can read them from a single-horizon
`python -m wisecat.backtest --horizon X` run if you need them).

Output also includes a few mechanical tuning hints based on a strategy's
hit rate at its diagonal forward window:

    hit < 50%        → weight should be 0 (worse than coin flip)
    50% ≤ hit < 52%  → weight should be ≤ 0.10 (barely an edge)
    52% ≤ hit < 55%  → modest edge (current weight reasonable)
    hit ≥ 55%        → strong edge (consider increasing weight)

The hints don't overwrite weights — they suggest. Final weights are a
human call (the hit-rate threshold ignores Sharpe, drawdown, signal
correlation, all of which matter).

CLI:
    python -m wisecat.tune --ticker SPY --start 2010-01-01
    python -m wisecat.tune --ticker AAPL --start 2018-01-01 --threshold 0.3
"""

from __future__ import annotations

import argparse
from datetime import date

from .backtest import run_backtest, BacktestResult
from .strategies import HORIZONS, STRATEGY_WEIGHTS_BY_HORIZON
from .yfinance_client import get_full_history

# Native forward window per horizon — the "diagonal" of the tuning grid.
NATIVE_WINDOW: dict[str, int] = {"1W": 5, "1M": 21, "1Y": 252}


def _hint(weight: float, hit: float, n: int) -> str:
    if n < 50 or weight == 0.0:
        return ""
    if hit < 0.50:
        return "↓ sub coin-flip — consider 0.0"
    if hit < 0.52:
        return "↘ marginal — cap ≤ 0.10"
    if hit < 0.55:
        return "≈ modest edge"
    return "↑ strong edge — consider raising"


def _format_weight_hit(weight: float, hit: float, n: int) -> str:
    if weight == 0.0 and n == 0:
        return "  —    "
    return f"{weight:.2f}  {hit*100:5.1f}%"


def _run_all_horizons(
    ticker: str,
    start: date,
    end: date | None,
    threshold: float,
    long_only: bool,
) -> dict[str, BacktestResult]:
    df = get_full_history(ticker)
    return {
        h: run_backtest(
            ticker,
            start=start,
            end=end,
            threshold=threshold,
            long_only=long_only,
            horizon=h,
            history=df,
        )
        for h in HORIZONS
    }


def _print_tuning_report(results: dict[str, BacktestResult]) -> None:
    sample = results["1M"]
    print(f"\n=== Tuning report: {sample.ticker} "
          f"({sample.start_date} → {sample.end_date}) ===")
    print(f"Decision days:  {sample.n_decision_days}")
    print(f"Threshold:      {sample.threshold:.2f}")
    print()

    # Per-strategy diagonal table.
    all_strategies = list(STRATEGY_WEIGHTS_BY_HORIZON["1M"].keys())
    header = f"{'strategy':25} {'1W (×5d)':>14} {'1M (×21d)':>14} {'1Y (×252d)':>14}"
    print(header)
    print(f"{'':25} {'wt   hit':>14} {'wt   hit':>14} {'wt   hit':>14}")
    print("-" * len(header))

    hints: list[tuple[str, str, str]] = []  # (horizon, strategy, hint)

    for name in all_strategies:
        cells = []
        for h in HORIZONS:
            r = results[h]
            window = NATIVE_WINDOW[h]
            weight = STRATEGY_WEIGHTS_BY_HORIZON[h].get(name, 0.0)
            hit = r.per_strategy_hit_rate_by_window.get(window, {}).get(name, 0.0)
            n = r.per_strategy_n_by_window.get(window, {}).get(name, 0)
            cells.append(_format_weight_hit(weight, hit, n))
            hint = _hint(weight, hit, n)
            if hint:
                hints.append((h, name, hint))
        print(f"  {name:23} {cells[0]:>14} {cells[1]:>14} {cells[2]:>14}")

    print()
    print(f"{'':27} {'1W':>14} {'1M':>14} {'1Y':>14}")
    print(f"  {'Composite Sharpe':23} "
          f"{results['1W'].strategy_sharpe:>14.2f} "
          f"{results['1M'].strategy_sharpe:>14.2f} "
          f"{results['1Y'].strategy_sharpe:>14.2f}")
    print(f"  {'Strategy total return':23} "
          f"{_pct(results['1W'].strategy_total_return):>14} "
          f"{_pct(results['1M'].strategy_total_return):>14} "
          f"{_pct(results['1Y'].strategy_total_return):>14}")
    print(f"  {'Buy & hold total return':23} "
          f"{_pct(results['1W'].buy_hold_total_return):>14} "
          f"{_pct(results['1M'].buy_hold_total_return):>14} "
          f"{_pct(results['1Y'].buy_hold_total_return):>14}")
    print(f"  {'Time long':23} "
          f"{_pct_pos(results['1W'].pct_long):>14} "
          f"{_pct_pos(results['1M'].pct_long):>14} "
          f"{_pct_pos(results['1Y'].pct_long):>14}")
    print(f"  {'Max drawdown':23} "
          f"{_pct(results['1W'].strategy_max_dd):>14} "
          f"{_pct(results['1M'].strategy_max_dd):>14} "
          f"{_pct(results['1Y'].strategy_max_dd):>14}")

    if hints:
        print()
        print("Tuning hints:")
        for h, name, msg in hints:
            print(f"  • [{h}] {name:23} {msg}")
    print()


def _pct(x: float) -> str:
    return f"{x*100:+.1f}%"


def _pct_pos(x: float) -> str:
    return f"{x*100:.0f}%"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Per-horizon weight tuning report (runs 1W / 1M / 1Y backtests on one history pull)."
    )
    parser.add_argument("--ticker", required=True)
    parser.add_argument("--start", required=True, help="YYYY-MM-DD")
    parser.add_argument("--end", default=None, help="YYYY-MM-DD")
    parser.add_argument("--threshold", type=float, default=0.5)
    parser.add_argument(
        "--allow-shorts",
        action="store_true",
        help="Take short positions when composite < -threshold (default: long-only).",
    )
    args = parser.parse_args()

    start = date.fromisoformat(args.start)
    end = date.fromisoformat(args.end) if args.end else None

    results = _run_all_horizons(
        ticker=args.ticker,
        start=start,
        end=end,
        threshold=args.threshold,
        long_only=not args.allow_shorts,
    )
    _print_tuning_report(results)


if __name__ == "__main__":
    main()
