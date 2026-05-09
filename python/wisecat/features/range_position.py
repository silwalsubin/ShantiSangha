"""Continuous candle-pattern features.

Replaces named patterns (hammer, shooting star, doji) with the underlying
continuous quantities they all crudely encode: where in the day's range
did price close, how big was the body relative to recent volatility, and
how long were the wicks. The GBM picks up whatever signal exists without
us hand-coding pattern recipes.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import pandas as pd

if TYPE_CHECKING:
    from . import FeatureContext


_ATR_WINDOW = 14
_AVG_WINDOW = 5


def _bar_range_position(open_: float, high: float, low: float, close: float) -> float:
    rng = high - low
    if rng <= 0 or pd.isna(rng):
        return 0.5
    pos = (close - low) / rng
    if pd.isna(pos):
        return 0.5
    return float(max(0.0, min(1.0, pos)))


def _atr(df: pd.DataFrame, window: int) -> float | None:
    if len(df) < window + 1:
        return None
    high = df["high"].astype(float)
    low = df["low"].astype(float)
    close = df["close"].astype(float)
    prev_close = close.shift(1)
    tr = pd.concat([
        (high - low).abs(),
        (high - prev_close).abs(),
        (low - prev_close).abs(),
    ], axis=1).max(axis=1)
    atr = tr.rolling(window).mean().iloc[-1]
    if pd.isna(atr) or atr <= 0:
        return None
    return float(atr)


def compute(df: pd.DataFrame, context: "FeatureContext") -> dict[str, float]:
    needed = {"open", "high", "low", "close"}
    if len(df) == 0 or not needed.issubset(df.columns):
        return {}

    df_sorted = df.sort_values("date").reset_index(drop=True) if "date" in df.columns else df.reset_index(drop=True)

    last = df_sorted.iloc[-1]
    o = float(last["open"])
    h = float(last["high"])
    l = float(last["low"])
    c = float(last["close"])

    out: dict[str, float] = {}

    # range_position_today
    out["range_position_today"] = _bar_range_position(o, h, l, c)

    # range_position_5d_avg — average over the last 5 bars (or whatever exists)
    tail = df_sorted.tail(_AVG_WINDOW)
    if len(tail) > 0:
        positions = []
        for _, row in tail.iterrows():
            try:
                positions.append(_bar_range_position(
                    float(row["open"]), float(row["high"]), float(row["low"]), float(row["close"])
                ))
            except (TypeError, ValueError):
                continue
        if positions:
            avg = sum(positions) / len(positions)
            if not pd.isna(avg):
                out["range_position_5d_avg"] = float(avg)

    # body_to_atr_ratio — needs ATR(14)
    atr = _atr(df_sorted, _ATR_WINDOW)
    if atr is not None and atr > 0:
        body = abs(c - o)
        ratio = body / atr
        if not pd.isna(ratio):
            out["body_to_atr_ratio"] = float(ratio)

    # wicks
    rng = h - l
    if rng <= 0 or pd.isna(rng):
        out["upper_wick_pct"] = 0.0
        out["lower_wick_pct"] = 0.0
    else:
        upper = (h - max(o, c)) / rng
        lower = (min(o, c) - l) / rng
        out["upper_wick_pct"] = float(max(0.0, min(1.0, upper))) if not pd.isna(upper) else 0.0
        out["lower_wick_pct"] = float(max(0.0, min(1.0, lower))) if not pd.isna(lower) else 0.0

    return out
