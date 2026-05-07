"""Backtest harness for the technical strategy ensemble.

For each trading day in the requested window, computes the composite
technical score using **only bars on or before that day** (no lookahead),
then takes a long/flat/short position for the next day's bar based on
that score:

    composite > +threshold  → long  (+1)
    composite < -threshold  → short (-1)
    otherwise               → flat  ( 0)

Daily P&L = position × (next_close / cur_close − 1). Reports total return,
annualized return, Sharpe, and max drawdown vs. buy-and-hold, plus a
per-strategy hit rate (does each strategy's *sign* match the direction of
the next day's move?).

The strategy here is the **technical-only** ensemble — no astro overlay.
That keeps the backtest reproducible from price data alone.

CLI:
    python -m wisecat.backtest --ticker AAPL --start 2020-01-01
    python -m wisecat.backtest --ticker SPY  --start 2018-01-01 --threshold 0.3
"""

from __future__ import annotations

import argparse
import math
from dataclasses import dataclass, field
from datetime import date

import pandas as pd

from .scoring import score_ticker
from .strategies import ALL_STRATEGIES
from .yfinance_client import get_full_history


@dataclass
class BacktestResult:
    ticker: str
    start_date: date
    end_date: date
    n_decision_days: int
    threshold: float
    pct_long: float
    pct_short: float
    pct_flat: float
    strategy_total_return: float
    buy_hold_total_return: float
    strategy_annual_return: float
    buy_hold_annual_return: float
    strategy_sharpe: float
    buy_hold_sharpe: float
    strategy_max_dd: float
    buy_hold_max_dd: float
    per_strategy_hit_rate: dict[str, float] = field(default_factory=dict)
    per_strategy_n: dict[str, int] = field(default_factory=dict)


def _annualized_return(daily_returns: pd.Series) -> float:
    if daily_returns.empty:
        return 0.0
    n = len(daily_returns)
    cum = float((1 + daily_returns).prod())
    if cum <= 0:
        return -1.0
    return cum ** (252 / n) - 1


def _sharpe(daily_returns: pd.Series) -> float:
    if daily_returns.empty or daily_returns.std(ddof=0) == 0:
        return 0.0
    return float(daily_returns.mean() / daily_returns.std(ddof=0) * math.sqrt(252))


def _max_drawdown(daily_returns: pd.Series) -> float:
    if daily_returns.empty:
        return 0.0
    cum = (1 + daily_returns).cumprod()
    running_max = cum.cummax()
    drawdown = cum / running_max - 1
    return float(drawdown.min())


def run_backtest(
    ticker: str,
    start: date,
    end: date | None = None,
    threshold: float = 0.5,
    long_only: bool = True,
    history: pd.DataFrame | None = None,
) -> BacktestResult:
    """Simulate the technical-only ensemble. Pass `history` to inject a fixed
    DataFrame (used by tests); otherwise pulls full daily history via yfinance.

    long_only=True (the default) maps would-be shorts to flat. The 16-year
    SPY backtest showed shorting gave back ~20% of strategy return — equity
    benchmarks have a structural long bias and shorting them fights that.
    """
    df = history if history is not None else get_full_history(ticker)
    if df.empty:
        raise ValueError(f"no history for {ticker}")

    df = df.sort_values("date").reset_index(drop=True)

    # Need at least 274 prior bars before any decision so the longest-window
    # strategy (12-1 momentum) has the data it needs.
    min_history = 274
    in_window = df.index[df["date"] >= start].tolist()
    if not in_window:
        raise ValueError(f"no bars on or after {start}")
    first_idx = max(min_history, in_window[0])

    end = end or df["date"].iloc[-1]
    in_end = df.index[df["date"] <= end].tolist()
    if not in_end:
        raise ValueError(f"no bars on or before {end}")
    # last_idx is the last day we *score*; we still need bar i+1 to compute
    # next-day return, so cap at len-2.
    last_idx = min(in_end[-1], len(df) - 2)
    if first_idx >= last_idx:
        raise ValueError(
            f"insufficient history: need ≥ {min_history} bars before {start}"
        )

    positions: list[float] = []
    daily_pnl: list[float] = []
    decision_dates: list = []
    bh_returns: list[float] = []
    per_signs: dict[str, list[int]] = {name: [] for name, _ in ALL_STRATEGIES}
    per_correct: dict[str, list[int]] = {name: [] for name, _ in ALL_STRATEGIES}

    for i in range(first_idx, last_idx + 1):
        slice_df = df.iloc[: i + 1]
        score = score_ticker(ticker, slice_df, price=float(slice_df["close"].iloc[-1]))
        composite = score.technical_score

        if composite > threshold:
            position = 1.0
        elif composite < -threshold and not long_only:
            position = -1.0
        else:
            position = 0.0
        positions.append(position)

        cur_close = float(df["close"].iloc[i])
        next_close = float(df["close"].iloc[i + 1])
        next_ret = next_close / cur_close - 1.0 if cur_close else 0.0
        daily_pnl.append(position * next_ret)
        bh_returns.append(next_ret)
        decision_dates.append(df["date"].iloc[i])

        for sig in score.signals:
            sign = 1 if sig.contribution > 0 else (-1 if sig.contribution < 0 else 0)
            if sign != 0:
                per_signs[sig.name].append(sign)
                per_correct[sig.name].append(int((sign > 0) == (next_ret > 0)))

    pnl = pd.Series(daily_pnl, index=pd.to_datetime(decision_dates))
    bh = pd.Series(bh_returns, index=pd.to_datetime(decision_dates))

    n = len(positions)
    n_long = sum(1 for p in positions if p > 0)
    n_short = sum(1 for p in positions if p < 0)
    n_flat = n - n_long - n_short

    per_hit = {
        name: (sum(c) / len(c) if c else 0.0)
        for name, c in per_correct.items()
    }
    per_n = {name: len(c) for name, c in per_correct.items()}

    return BacktestResult(
        ticker=ticker,
        start_date=df["date"].iloc[first_idx],
        end_date=df["date"].iloc[last_idx],
        n_decision_days=n,
        threshold=threshold,
        pct_long=n_long / n,
        pct_short=n_short / n,
        pct_flat=n_flat / n,
        strategy_total_return=float((1 + pnl).prod() - 1),
        buy_hold_total_return=float((1 + bh).prod() - 1),
        strategy_annual_return=_annualized_return(pnl),
        buy_hold_annual_return=_annualized_return(bh),
        strategy_sharpe=_sharpe(pnl),
        buy_hold_sharpe=_sharpe(bh),
        strategy_max_dd=_max_drawdown(pnl),
        buy_hold_max_dd=_max_drawdown(bh),
        per_strategy_hit_rate=per_hit,
        per_strategy_n=per_n,
    )


def _fmt_pct(x: float) -> str:
    return f"{x*100:+.2f}%"


def _print_report(r: BacktestResult) -> None:
    print(f"\n=== Backtest: {r.ticker} ({r.start_date} → {r.end_date}) ===")
    print(f"Decision days:  {r.n_decision_days}")
    print(f"Threshold:      {r.threshold:.2f}")
    print(f"Position mix:   {r.pct_long*100:.0f}% long / "
          f"{r.pct_short*100:.0f}% short / {r.pct_flat*100:.0f}% flat")
    print()
    print(f"{'':24}{'Strategy':>12}{'Buy & Hold':>14}")
    print("-" * 50)
    print(f"{'Total return':24}{_fmt_pct(r.strategy_total_return):>12}"
          f"{_fmt_pct(r.buy_hold_total_return):>14}")
    print(f"{'Annualized return':24}{_fmt_pct(r.strategy_annual_return):>12}"
          f"{_fmt_pct(r.buy_hold_annual_return):>14}")
    print(f"{'Sharpe (annualized)':24}{r.strategy_sharpe:>12.2f}"
          f"{r.buy_hold_sharpe:>14.2f}")
    print(f"{'Max drawdown':24}{_fmt_pct(r.strategy_max_dd):>12}"
          f"{_fmt_pct(r.buy_hold_max_dd):>14}")
    print()
    print("Per-strategy hit rate (sign matches next-day move):")
    for name in r.per_strategy_hit_rate:
        n = r.per_strategy_n[name]
        hit = r.per_strategy_hit_rate[name]
        print(f"  {name:25} {hit*100:5.1f}%   (n={n})")


def main() -> None:
    parser = argparse.ArgumentParser(description="Backtest the wisecat technical ensemble")
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

    r = run_backtest(
        args.ticker,
        start=start,
        end=end,
        threshold=args.threshold,
        long_only=not args.allow_shorts,
    )
    _print_report(r)


if __name__ == "__main__":
    main()
