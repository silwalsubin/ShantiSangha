"""Parallel basket tuning: run the multi-horizon tune across a list of
tickers and report micro-averaged per-strategy hit rates at each horizon's
native forward window.

The single-ticker `wisecat.tune` is too noisy on its own — momentum-friendly
names like AAPL make trend signals look brilliant and oscillators look
broken; a beaten-down name might invert that. To choose weights you need a
basket. This module runs the underlying backtest per ticker in parallel,
pools the (correct, total) samples across the basket, then prints one
consolidated diagonal table.

Default basket = `data/nasdaq100.txt` (curated). Tickers without enough
history at the requested start date are skipped, not failed.

CLI:
    python -m wisecat.tune_basket --start 2014-01-01
    python -m wisecat.tune_basket --start 2018-01-01 --workers 12
    python -m wisecat.tune_basket --tickers AAPL,MSFT,GOOGL --start 2014-01-01

The threshold default matches `wisecat.tune` (0.5) — per-strategy hit rate
is independent of threshold, only the ensemble Sharpe / total return cells
shift with it. Hit-rate tuning hints (the headline output) are unaffected.
"""

from __future__ import annotations

import argparse
import math
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from datetime import date
from pathlib import Path

from .backtest import run_backtest, BacktestResult
from .strategies import HORIZONS, STRATEGY_WEIGHTS_BY_HORIZON

# Native forward window per horizon — the diagonal of the tuning grid.
NATIVE_WINDOW: dict[str, int] = {"1W": 5, "1M": 21, "1Y": 252}

DEFAULT_BASKET = Path(__file__).parent / "data" / "nasdaq100.txt"


def _load_tickers(path: Path) -> list[str]:
    out: list[str] = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        # First whitespace-separated token; drop trailing comments.
        ticker = line.split()[0].upper()
        if ticker:
            out.append(ticker)
    return out


def _run_one_ticker(
    ticker: str,
    start: date,
    end: date | None,
    threshold: float,
    long_only: bool,
) -> tuple[str, dict[str, BacktestResult] | None, str | None]:
    try:
        results: dict[str, BacktestResult] = {}
        for horizon in HORIZONS:
            results[horizon] = run_backtest(
                ticker,
                start=start,
                end=end,
                threshold=threshold,
                long_only=long_only,
                horizon=horizon,
            )
        return ticker, results, None
    except Exception as e:
        return ticker, None, f"{type(e).__name__}: {e}"


def run_basket(
    tickers: list[str],
    start: date,
    end: date | None,
    threshold: float,
    long_only: bool,
    workers: int,
    progress: bool = True,
) -> tuple[dict[str, dict[str, BacktestResult]], dict[str, str]]:
    """Run the per-horizon backtest for each ticker in parallel.

    Uses a process pool, not a thread pool. The pandas / ta operations
    inside `score_ticker` hold the GIL long enough that threads gave us
    ~1.3 effective cores on 8 workers (≈30 min for the NASDAQ-100); a
    process pool gets true 8x and finishes the same basket in ~5 min.
    Workers re-import `wisecat.*` on spawn (~1s each) — amortizes against
    the per-ticker compute trivially.

    Returns (results_by_ticker, errors_by_ticker). Tickers that hit
    insufficient-history checks land in `errors_by_ticker` with a short
    reason — not raised — so a single missing name doesn't kill the basket.
    """
    results: dict[str, dict[str, BacktestResult]] = {}
    errors: dict[str, str] = {}
    started = time.monotonic()
    total = len(tickers)
    completed = 0

    with ProcessPoolExecutor(max_workers=workers) as pool:
        futures = {
            pool.submit(_run_one_ticker, t, start, end, threshold, long_only): t
            for t in tickers
        }
        for future in as_completed(futures):
            ticker, ticker_results, err = future.result()
            completed += 1
            if err is not None:
                errors[ticker] = err
                status = f"  ✗ {ticker:8} {err}"
            else:
                results[ticker] = ticker_results
                status = f"  ✓ {ticker:8} ok"
            if progress:
                elapsed = time.monotonic() - started
                rate = completed / elapsed if elapsed > 0 else 0.0
                eta = (total - completed) / rate if rate > 0 else 0.0
                print(f"[{completed}/{total}] {status}  (eta {eta:.0f}s)",
                      file=sys.stderr, flush=True)

    return results, errors


def aggregate(
    results: dict[str, dict[str, BacktestResult]],
) -> dict[tuple[str, int, str], tuple[int, int]]:
    """Pool (correct, total) samples across the basket per (horizon, window, strategy)."""
    pooled: dict[tuple[str, int, str], tuple[int, int]] = {}
    for ticker, by_horizon in results.items():
        for horizon, br in by_horizon.items():
            for window, per_strategy in br.per_strategy_n_by_window.items():
                for strategy, n in per_strategy.items():
                    if n <= 0:
                        continue
                    rate = br.per_strategy_hit_rate_by_window[window].get(strategy, 0.0)
                    correct = int(round(rate * n))
                    key = (horizon, window, strategy)
                    prev_correct, prev_n = pooled.get(key, (0, 0))
                    pooled[key] = (prev_correct + correct, prev_n + n)
    return pooled


def aggregate_ensemble(
    results: dict[str, dict[str, BacktestResult]],
) -> dict[str, dict[str, float]]:
    """Average ensemble-level metrics across the basket per horizon."""
    out: dict[str, dict[str, float]] = {}
    for horizon in HORIZONS:
        sharpes = []
        totals = []
        bh_totals = []
        max_dds = []
        long_pcts = []
        for ticker, by_horizon in results.items():
            br = by_horizon.get(horizon)
            if br is None:
                continue
            sharpes.append(br.strategy_sharpe)
            totals.append(br.strategy_total_return)
            bh_totals.append(br.buy_hold_total_return)
            max_dds.append(br.strategy_max_dd)
            long_pcts.append(br.pct_long)
        out[horizon] = {
            "sharpe_mean": _mean(sharpes),
            "sharpe_median": _median(sharpes),
            "total_mean": _mean(totals),
            "bh_total_mean": _mean(bh_totals),
            "max_dd_mean": _mean(max_dds),
            "long_pct_mean": _mean(long_pcts),
        }
    return out


def _mean(xs: list[float]) -> float:
    return sum(xs) / len(xs) if xs else 0.0


def _median(xs: list[float]) -> float:
    if not xs:
        return 0.0
    s = sorted(xs)
    mid = len(s) // 2
    if len(s) % 2 == 1:
        return s[mid]
    return (s[mid - 1] + s[mid]) / 2


def _hint(weight: float, hit: float, n: int) -> str:
    if n < 100 or weight == 0.0:
        return ""
    if hit < 0.50:
        return "↓ sub coin-flip — consider 0.0"
    if hit < 0.52:
        return "↘ marginal — cap ≤ 0.10"
    if hit < 0.55:
        return "≈ modest edge"
    return "↑ strong edge — consider raising"


def _format_cell(weight: float, hit_rate: float | None, n: int) -> str:
    if hit_rate is None or n == 0:
        return "  —    "
    return f"{weight:.2f}  {hit_rate*100:5.1f}% (n={n})"


def print_report(
    tickers_run: list[str],
    errors: dict[str, str],
    pooled: dict[tuple[str, int, str], tuple[int, int]],
    ensemble: dict[str, dict[str, float]],
) -> None:
    print()
    print(f"=== Basket tuning report ===")
    print(f"Tickers requested:  {len(tickers_run)}")
    print(f"Tickers completed:  {len(tickers_run) - len(errors)}")
    print(f"Tickers skipped:    {len(errors)} (insufficient history / fetch failed)")
    if errors:
        skipped = sorted(errors.keys())
        print(f"  → {', '.join(skipped[:8])}" + (" …" if len(skipped) > 8 else ""))
    print()

    all_strategies = list(STRATEGY_WEIGHTS_BY_HORIZON["1M"].keys())
    header = (f"{'strategy':25} "
              f"{'1W (×5d)':>22} {'1M (×21d)':>22} {'1Y (×252d)':>22}")
    print(header)
    print(f"{'':25} {'wt   hit (samples)':>22} "
          f"{'wt   hit (samples)':>22} {'wt   hit (samples)':>22}")
    print("-" * len(header))

    hints: list[tuple[str, str, str]] = []
    for strategy in all_strategies:
        cells: list[str] = []
        for horizon in HORIZONS:
            window = NATIVE_WINDOW[horizon]
            weight = STRATEGY_WEIGHTS_BY_HORIZON[horizon].get(strategy, 0.0)
            correct, n = pooled.get((horizon, window, strategy), (0, 0))
            hit = (correct / n) if n > 0 else None
            cells.append(_format_cell(weight, hit, n))
            if hit is not None:
                msg = _hint(weight, hit, n)
                if msg:
                    hints.append((horizon, strategy, msg))
        print(f"  {strategy:23} {cells[0]:>22} {cells[1]:>22} {cells[2]:>22}")

    print()
    print(f"{'':27} {'1W':>14} {'1M':>14} {'1Y':>14}")
    e = ensemble
    print(f"  {'Ensemble Sharpe (mean)':25} "
          f"{e['1W']['sharpe_mean']:>14.2f} "
          f"{e['1M']['sharpe_mean']:>14.2f} "
          f"{e['1Y']['sharpe_mean']:>14.2f}")
    print(f"  {'Ensemble Sharpe (median)':25} "
          f"{e['1W']['sharpe_median']:>14.2f} "
          f"{e['1M']['sharpe_median']:>14.2f} "
          f"{e['1Y']['sharpe_median']:>14.2f}")
    print(f"  {'Mean total return':25} "
          f"{_pct(e['1W']['total_mean']):>14} "
          f"{_pct(e['1M']['total_mean']):>14} "
          f"{_pct(e['1Y']['total_mean']):>14}")
    print(f"  {'Mean buy-and-hold':25} "
          f"{_pct(e['1W']['bh_total_mean']):>14} "
          f"{_pct(e['1M']['bh_total_mean']):>14} "
          f"{_pct(e['1Y']['bh_total_mean']):>14}")
    print(f"  {'Mean max drawdown':25} "
          f"{_pct(e['1W']['max_dd_mean']):>14} "
          f"{_pct(e['1M']['max_dd_mean']):>14} "
          f"{_pct(e['1Y']['max_dd_mean']):>14}")
    print(f"  {'Mean time long':25} "
          f"{_pct_pos(e['1W']['long_pct_mean']):>14} "
          f"{_pct_pos(e['1M']['long_pct_mean']):>14} "
          f"{_pct_pos(e['1Y']['long_pct_mean']):>14}")

    if hints:
        print()
        print("Tuning hints (basket-pooled hit rate):")
        for h, name, msg in hints:
            print(f"  • [{h}] {name:23} {msg}")
    print()


def _pct(x: float) -> str:
    return f"{x*100:+.1f}%"


def _pct_pos(x: float) -> str:
    return f"{x*100:.0f}%"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Per-horizon weight tuning on a basket of tickers (parallel)."
    )
    parser.add_argument("--start", required=True, help="YYYY-MM-DD")
    parser.add_argument("--end", default=None, help="YYYY-MM-DD")
    parser.add_argument("--threshold", type=float, default=0.5)
    parser.add_argument(
        "--workers",
        type=int,
        default=8,
        help="Parallel workers (threads). Default: 8.",
    )
    parser.add_argument(
        "--tickers",
        default=None,
        help="Comma-separated ticker list. If omitted, loads data/nasdaq100.txt.",
    )
    parser.add_argument(
        "--basket",
        type=Path,
        default=DEFAULT_BASKET,
        help="Path to a basket file (one ticker per line). Used when --tickers is omitted.",
    )
    parser.add_argument(
        "--allow-shorts",
        action="store_true",
        help="Take short positions when composite < -threshold (default: long-only).",
    )
    args = parser.parse_args()

    if args.tickers:
        tickers = [t.strip().upper() for t in args.tickers.split(",") if t.strip()]
    else:
        tickers = _load_tickers(args.basket)

    if not tickers:
        raise SystemExit("no tickers to run")

    start = date.fromisoformat(args.start)
    end = date.fromisoformat(args.end) if args.end else None

    print(f"Running basket tune on {len(tickers)} tickers "
          f"from {start} with {args.workers} workers…", file=sys.stderr)

    results, errors = run_basket(
        tickers=tickers,
        start=start,
        end=end,
        threshold=args.threshold,
        long_only=not args.allow_shorts,
        workers=args.workers,
        progress=True,
    )

    if not results:
        raise SystemExit("no tickers completed successfully")

    pooled = aggregate(results)
    ensemble = aggregate_ensemble(results)
    print_report(tickers, errors, pooled, ensemble)


if __name__ == "__main__":
    main()
