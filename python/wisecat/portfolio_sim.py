"""Portfolio probability simulator: 10 sector-diversified stocks, equal-weighted,
pooled forward-return distributions across best / worst / normal historical
regimes.

Answers the prior question to "is WiseCat right?" — namely, "what does naive
buy-and-hold of a sector-diversified basket actually do at each horizon, in
each regime?" The output is a distribution, not a single number, so the user
gets evidence-based probabilities (e.g. P(1Y return > 0) under the 2008/2020/
2022 worst-case pool).

What it does:
  - For each (regime, horizon) pair, pool forward H-day returns across all
    tickers in the basket and all date windows in the regime.
  - Report headline stats: sample count, P(>0), median, mean, p10, p90,
    worst, best, stdev.

What it does NOT do (deliberate v1 scope cuts):
  - No WiseCat scoring overlay — that's the v2 question.
  - No rebalancing / no portfolio P&L path — equal weighting is enforced by
    equal *sampling* across tickers. Marginal probabilities only.
  - No fees, slippage, dividends.
  - No cross-ticker correlation — pooled samples are treated independently,
    which understates portfolio-level drawdown risk.

CLI:
    python -m wisecat.portfolio_sim
    python -m wisecat.portfolio_sim --regimes worst
    python -m wisecat.portfolio_sim --tickers AAPL --regimes worst --horizons 1M,1Y
"""

from __future__ import annotations

import argparse
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import date
from typing import Iterable

import numpy as np
import pandas as pd

from .yfinance_client import YFinanceUnavailable, get_full_history


# One representative mega-cap per GICS sector. APD over LIN for Materials —
# the post-Praxair-merger LIN only has US-listed history from Oct 2018, which
# would silently drop the 2008 GFC window.
SECTOR_BASKET: dict[str, str] = {
    "Information Technology": "AAPL",
    "Health Care":             "JNJ",
    "Financials":              "JPM",
    "Consumer Discretionary":  "HD",
    "Consumer Staples":        "PG",
    "Communication Services":  "VZ",
    "Industrials":             "CAT",
    "Energy":                  "XOM",
    "Utilities":               "NEE",
    "Materials":               "APD",
}

# Forward window in *trading days*, matching tune_basket.NATIVE_WINDOW.
HORIZONS_DAYS: dict[str, int] = {"1W": 5, "1M": 21, "1Y": 252}

# Each regime is a list of (start, end) windows. Forward returns are computed
# for entries with t in [start, end] *and* t + H trading days available in the
# full history. We deliberately pool multiple windows per regime so no single
# year carries the conclusion.
REGIMES: dict[str, list[tuple[date, date]]] = {
    "best": [
        (date(2017, 1, 1),  date(2018, 1, 31)),   # steady low-vol grind
        (date(2019, 1, 1),  date(2019, 12, 31)),  # post-Q4-2018 recovery
        (date(2023, 1, 1),  date(2024, 6, 30)),   # AI-led bull
    ],
    "worst": [
        (date(2008, 9, 1),  date(2009, 3, 31)),   # GFC
        (date(2020, 2, 15), date(2020, 4, 15)),   # COVID crash
        (date(2022, 1, 1),  date(2022, 12, 31)),  # rate-hike bear
    ],
    "normal": [
        (date(2014, 1, 1),  date(2014, 12, 31)),  # mixed
        (date(2015, 1, 1),  date(2016, 6, 30)),   # sideways with Aug-2015 wobble
    ],
}


@dataclass(frozen=True)
class Summary:
    n: int
    p_positive: float
    median: float
    mean: float
    p10: float
    p90: float
    worst: float
    best: float
    stdev: float


def forward_returns(
    history: pd.DataFrame,
    window_start: date,
    window_end: date,
    horizon_days: int,
) -> np.ndarray:
    """Forward H-day total return for each trading day in [window_start, window_end]
    where the close price H trading days later is also available in `history`.

    Returns a 1-D float64 array. Empty array if no valid samples.
    """
    if history.empty:
        return np.empty(0, dtype=np.float64)

    closes = history["close"].to_numpy(dtype=np.float64)
    dates = history["date"].to_numpy()  # object array of datetime.date

    in_window = (dates >= np.datetime64(window_start)) & (dates <= np.datetime64(window_end))
    idx = np.flatnonzero(in_window)
    if idx.size == 0:
        return np.empty(0, dtype=np.float64)

    # Drop trailing indices where t + H falls past the end of history.
    valid = idx[idx + horizon_days < closes.size]
    if valid.size == 0:
        return np.empty(0, dtype=np.float64)

    entry = closes[valid]
    exit_ = closes[valid + horizon_days]
    # Guard against any zero or NaN closes (yfinance occasionally has gaps).
    ok = np.isfinite(entry) & np.isfinite(exit_) & (entry > 0)
    return (exit_[ok] / entry[ok]) - 1.0


def pool_regime(
    histories: dict[str, pd.DataFrame],
    windows: list[tuple[date, date]],
    horizon_days: int,
) -> np.ndarray:
    """Concatenate forward returns across all tickers × all windows.

    Equal weighting falls out of equal sampling: each ticker contributes the
    same set of trading-day entry points within each window, so its weight in
    the pooled distribution is structurally identical.
    """
    chunks: list[np.ndarray] = []
    for _, history in histories.items():
        for start, end in windows:
            r = forward_returns(history, start, end, horizon_days)
            if r.size:
                chunks.append(r)
    if not chunks:
        return np.empty(0, dtype=np.float64)
    return np.concatenate(chunks)


def summarize(returns: np.ndarray) -> Summary:
    if returns.size == 0:
        return Summary(0, float("nan"), float("nan"), float("nan"),
                       float("nan"), float("nan"), float("nan"), float("nan"), float("nan"))
    return Summary(
        n=int(returns.size),
        p_positive=float((returns > 0).mean()),
        median=float(np.median(returns)),
        mean=float(np.mean(returns)),
        p10=float(np.quantile(returns, 0.10)),
        p90=float(np.quantile(returns, 0.90)),
        worst=float(returns.min()),
        best=float(returns.max()),
        stdev=float(returns.std(ddof=1)) if returns.size > 1 else 0.0,
    )


def fetch_histories(tickers: Iterable[str], workers: int = 8) -> dict[str, pd.DataFrame]:
    """Parallel yfinance fetch (thread pool — I/O bound)."""
    tickers = list(tickers)
    out: dict[str, pd.DataFrame] = {}
    errors: dict[str, str] = {}

    def _one(t: str) -> tuple[str, pd.DataFrame | None, str | None]:
        try:
            return t, get_full_history(t), None
        except YFinanceUnavailable as e:
            return t, None, str(e)
        except Exception as e:
            return t, None, f"{type(e).__name__}: {e}"

    with ThreadPoolExecutor(max_workers=workers) as pool:
        for t, df, err in pool.map(_one, tickers):
            if err is not None:
                errors[t] = err
                print(f"  ! skipping {t}: {err}", file=sys.stderr)
                continue
            out[t] = df
            first = df["date"].iloc[0]
            last = df["date"].iloc[-1]
            print(f"  · {t:6} {len(df):>5} bars  {first} → {last}", file=sys.stderr)

    return out


def _pct(x: float, sign: bool = False) -> str:
    if not np.isfinite(x):
        return "  n/a"
    fmt = "+.2f" if sign else ".2f"
    return f"{x*100:{fmt}}%"


def print_regime(name: str, windows: list[tuple[date, date]],
                 horizons: list[str], summaries: dict[str, Summary]) -> None:
    label_map = {"best": "BEST CASE (bull)", "worst": "WORST CASE (drawdown)",
                 "normal": "NORMAL (sideways/mixed)"}
    label = label_map.get(name, name.upper())
    print()
    print(f"═══ {label} ═══")
    window_strs = ", ".join(f"{s} → {e}" for s, e in windows)
    print(f"Windows: {window_strs}")
    print()
    print(f"  {'horizon':10} {'n':>7}  {'P(>0)':>7}  "
          f"{'median':>9}  {'mean':>9}  {'p10':>9}  {'p90':>9}  "
          f"{'worst':>9}  {'best':>9}  {'stdev':>9}")
    for h in horizons:
        s = summaries[h]
        win = HORIZONS_DAYS[h]
        if s.n == 0:
            print(f"  {h} ({win}d)   no data")
            continue
        print(f"  {h} ({win}d){'':<3} "
              f"{s.n:>7}  "
              f"{s.p_positive:>7.3f}  "
              f"{_pct(s.median, sign=True):>9}  "
              f"{_pct(s.mean, sign=True):>9}  "
              f"{_pct(s.p10, sign=True):>9}  "
              f"{_pct(s.p90, sign=True):>9}  "
              f"{_pct(s.worst, sign=True):>9}  "
              f"{_pct(s.best, sign=True):>9}  "
              f"{_pct(s.stdev):>9}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Pooled forward-return distributions for a sector-diversified "
                    "equal-weighted basket across historical regimes."
    )
    parser.add_argument(
        "--tickers",
        default=None,
        help="Comma-separated ticker list. If omitted, uses the 10-sector default basket.",
    )
    parser.add_argument(
        "--regimes",
        default="best,worst,normal",
        help="Comma-separated regime names. Default: best,worst,normal.",
    )
    parser.add_argument(
        "--horizons",
        default="1W,1M,1Y",
        help="Comma-separated horizons. Default: 1W,1M,1Y.",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=8,
        help="Parallel workers for yfinance fetch. Default: 8.",
    )
    args = parser.parse_args()

    if args.tickers:
        tickers = [t.strip().upper() for t in args.tickers.split(",") if t.strip()]
    else:
        tickers = list(SECTOR_BASKET.values())

    regimes = [r.strip().lower() for r in args.regimes.split(",") if r.strip()]
    for r in regimes:
        if r not in REGIMES:
            raise SystemExit(f"unknown regime: {r}  (choices: {sorted(REGIMES)})")

    horizons = [h.strip() for h in args.horizons.split(",") if h.strip()]
    for h in horizons:
        if h not in HORIZONS_DAYS:
            raise SystemExit(f"unknown horizon: {h}  (choices: {sorted(HORIZONS_DAYS)})")

    print("=== Portfolio Probability Simulator ===", file=sys.stderr)
    print(f"Basket: {len(tickers)} tickers, equal-weighted", file=sys.stderr)
    if not args.tickers:
        for sector, ticker in SECTOR_BASKET.items():
            print(f"  {ticker:6} {sector}", file=sys.stderr)
    print(f"Regimes: {', '.join(regimes)}", file=sys.stderr)
    print(f"Horizons: {', '.join(horizons)}", file=sys.stderr)
    print(file=sys.stderr)
    print("Fetching histories…", file=sys.stderr)

    histories = fetch_histories(tickers, workers=args.workers)
    if not histories:
        raise SystemExit("no histories fetched — cannot continue")

    for regime in regimes:
        windows = REGIMES[regime]
        summaries: dict[str, Summary] = {}
        for h in horizons:
            pooled = pool_regime(histories, windows, HORIZONS_DAYS[h])
            summaries[h] = summarize(pooled)
        print_regime(regime, windows, horizons, summaries)
    print()


if __name__ == "__main__":
    main()
