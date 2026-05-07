"""Backtest harness for the technical strategy ensemble.

For each trading day in the requested window, computes the composite
technical score for one horizon (1W / 1M / 1Y) using **only bars on or
before that day** (no lookahead), then takes a long/flat/short position
for the next day's bar based on that score:

    composite > +threshold  → long  (+1)
    composite < -threshold  → short (-1)
    otherwise               → flat  ( 0)

Daily P&L = position × (next_close / cur_close − 1). Reports total return,
annualized return, Sharpe, and max drawdown vs. buy-and-hold, plus a
per-strategy hit rate (does each strategy's *sign* match the direction of
the next day's move?) — and additionally at the 5/21/252-day forward
windows that match the three horizons. The diagonal of that table —
1W weights × 5d window, 1M × 21d, 1Y × 252d — is the load-bearing
evidence for the per-horizon weight choices.

The strategy here is the **technical-only** ensemble — no astro overlay.
That keeps the backtest reproducible from price data alone.

CLI:
    python -m wisecat.backtest --ticker AAPL --start 2020-01-01
    python -m wisecat.backtest --ticker SPY  --start 2010-01-01 --horizon 1Y
"""

from __future__ import annotations

import argparse
import math
from dataclasses import dataclass, field
from datetime import date

import pandas as pd

from .scoring import score_ticker
from .strategies import ALL_STRATEGIES, HORIZONS
from .yfinance_client import get_full_history


FORWARD_WINDOWS: tuple[int, ...] = (1, 5, 21, 252)


@dataclass
class BacktestResult:
    ticker: str
    horizon: str
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
    # Hit rate per strategy at each forward window (1, 5, 21, 252 days).
    per_strategy_hit_rate_by_window: dict[int, dict[str, float]] = field(default_factory=dict)
    per_strategy_n_by_window: dict[int, dict[str, int]] = field(default_factory=dict)

    @property
    def per_strategy_hit_rate(self) -> dict[str, float]:
        """Legacy single-window view = next-day hit rate."""
        return self.per_strategy_hit_rate_by_window.get(1, {})

    @property
    def per_strategy_n(self) -> dict[str, int]:
        return self.per_strategy_n_by_window.get(1, {})


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
    horizon: str = "1M",
    history: pd.DataFrame | None = None,
) -> BacktestResult:
    """Simulate the technical-only ensemble at the requested horizon.

    `horizon` selects which weight vector to score with (1W / 1M / 1Y).
    P&L uses next-day return regardless of horizon — comparable across
    horizons. Per-strategy hit rate is reported at multiple forward
    windows so the diagonal of the 3×3 (horizon × forward-window) grid
    can be read off in one run.

    Pass `history` to inject a fixed DataFrame (used by tests); otherwise
    pulls full daily history via yfinance.

    long_only=True (the default) maps would-be shorts to flat. The 16-year
    SPY backtest showed shorting gave back ~20% of strategy return — equity
    benchmarks have a structural long bias and shorting them fights that.
    """
    if horizon not in HORIZONS:
        raise ValueError(f"unknown horizon {horizon!r}; must be one of {HORIZONS}")

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
    # per_signs[window][name] = list of signed contributions
    # per_correct[window][name] = list of 0/1 hits at that forward window
    per_signs: dict[int, dict[str, list[int]]] = {
        w: {name: [] for name, _ in ALL_STRATEGIES} for w in FORWARD_WINDOWS
    }
    per_correct: dict[int, dict[str, list[int]]] = {
        w: {name: [] for name, _ in ALL_STRATEGIES} for w in FORWARD_WINDOWS
    }

    closes = df["close"].astype(float).to_numpy()

    for i in range(first_idx, last_idx + 1):
        slice_df = df.iloc[: i + 1]
        score = score_ticker(ticker, slice_df, price=float(slice_df["close"].iloc[-1]))
        horizon_score = score.horizons.get(horizon)
        composite = horizon_score.score if horizon_score else 0.0

        if composite > threshold:
            position = 1.0
        elif composite < -threshold and not long_only:
            position = -1.0
        else:
            position = 0.0
        positions.append(position)

        cur_close = float(closes[i])
        next_close = float(closes[i + 1])
        next_ret = next_close / cur_close - 1.0 if cur_close else 0.0
        daily_pnl.append(position * next_ret)
        bh_returns.append(next_ret)
        decision_dates.append(df["date"].iloc[i])

        if not horizon_score:
            continue
        for sig in horizon_score.signals:
            sign = 1 if sig.contribution > 0 else (-1 if sig.contribution < 0 else 0)
            if sign == 0:
                continue
            for window in FORWARD_WINDOWS:
                fwd_idx = i + window
                if fwd_idx >= len(closes):
                    continue
                fwd_close = float(closes[fwd_idx])
                if cur_close == 0:
                    continue
                fwd_ret = fwd_close / cur_close - 1.0
                per_signs[window][sig.name].append(sign)
                per_correct[window][sig.name].append(int((sign > 0) == (fwd_ret > 0)))

    pnl = pd.Series(daily_pnl, index=pd.to_datetime(decision_dates))
    bh = pd.Series(bh_returns, index=pd.to_datetime(decision_dates))

    n = len(positions)
    n_long = sum(1 for p in positions if p > 0)
    n_short = sum(1 for p in positions if p < 0)
    n_flat = n - n_long - n_short

    per_hit_by_window = {
        window: {
            name: (sum(c) / len(c) if c else 0.0)
            for name, c in per_correct[window].items()
        }
        for window in FORWARD_WINDOWS
    }
    per_n_by_window = {
        window: {name: len(c) for name, c in per_correct[window].items()}
        for window in FORWARD_WINDOWS
    }

    return BacktestResult(
        ticker=ticker,
        horizon=horizon,
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
        per_strategy_hit_rate_by_window=per_hit_by_window,
        per_strategy_n_by_window=per_n_by_window,
    )


def _fmt_pct(x: float) -> str:
    return f"{x*100:+.2f}%"


def _print_report(r: BacktestResult) -> None:
    print(f"\n=== Backtest: {r.ticker} ({r.start_date} → {r.end_date}) ===")
    print(f"Horizon:        {r.horizon}")
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
    print("Per-strategy hit rate (sign matches forward move):")
    print(f"  {'strategy':25}{'1d':>10}{'5d':>10}{'21d':>10}{'252d':>10}")
    names = list(r.per_strategy_hit_rate_by_window[1].keys())
    for name in names:
        cells = []
        for window in FORWARD_WINDOWS:
            hit = r.per_strategy_hit_rate_by_window[window].get(name, 0.0)
            n = r.per_strategy_n_by_window[window].get(name, 0)
            cells.append(f"{hit*100:5.1f}% n={n}" if n else "       —")
        print(f"  {name:25}" + "".join(f"{c:>10}" for c in cells))


def main() -> None:
    parser = argparse.ArgumentParser(description="Backtest the wisecat technical ensemble")
    parser.add_argument("--ticker", required=True)
    parser.add_argument("--start", required=True, help="YYYY-MM-DD")
    parser.add_argument("--end", default=None, help="YYYY-MM-DD")
    parser.add_argument("--threshold", type=float, default=0.5)
    parser.add_argument(
        "--horizon",
        choices=list(HORIZONS),
        default="1M",
        help="Which horizon's weight vector to score with (default: 1M).",
    )
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
        horizon=args.horizon,
    )
    _print_report(r)


if __name__ == "__main__":
    main()
