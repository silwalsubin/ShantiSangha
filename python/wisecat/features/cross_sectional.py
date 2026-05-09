"""Cross-sectional return spread vs SPY at multiple horizons.

Captures relative momentum: a stock returning +20% while SPY returns +5%
is materially different from a stock returning +20% while SPY returns
+22%. The GBM consumes the spread as a single column per horizon.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import pandas as pd

if TYPE_CHECKING:
    from . import FeatureContext


_HORIZONS = {
    "xs_return_spread_3m_vs_spy": 63,
    "xs_return_spread_6m_vs_spy": 126,
    "xs_return_spread_1y_vs_spy": 252,
}


def compute(df: pd.DataFrame, context: "FeatureContext") -> dict[str, float]:
    spy = getattr(context, "spy_history", None)
    if spy is None or len(spy) == 0 or len(df) == 0:
        return {}
    if "date" not in df.columns or "date" not in spy.columns:
        return {}

    # Align on the most recent date present in BOTH frames.
    ticker_dates = set(df["date"])
    spy_dates = set(spy["date"])
    common = ticker_dates & spy_dates
    if not common:
        return {}
    anchor = max(common)

    df_sorted = df.sort_values("date").reset_index(drop=True)
    spy_sorted = spy.sort_values("date").reset_index(drop=True)

    df_idx = df_sorted.index[df_sorted["date"] == anchor]
    spy_idx = spy_sorted.index[spy_sorted["date"] == anchor]
    if len(df_idx) == 0 or len(spy_idx) == 0:
        return {}
    df_pos = int(df_idx[0])
    spy_pos = int(spy_idx[0])

    out: dict[str, float] = {}
    for key, lookback in _HORIZONS.items():
        if df_pos < lookback or spy_pos < lookback:
            continue
        try:
            t_now = float(df_sorted["close"].iloc[df_pos])
            t_then = float(df_sorted["close"].iloc[df_pos - lookback])
            s_now = float(spy_sorted["close"].iloc[spy_pos])
            s_then = float(spy_sorted["close"].iloc[spy_pos - lookback])
        except (IndexError, KeyError, ValueError):
            continue
        if t_then == 0 or s_then == 0:
            continue
        if pd.isna(t_now) or pd.isna(t_then) or pd.isna(s_now) or pd.isna(s_then):
            continue
        ticker_ret = t_now / t_then - 1.0
        spy_ret = s_now / s_then - 1.0
        spread = ticker_ret - spy_ret
        if pd.isna(spread):
            continue
        out[key] = float(spread)
    return out
