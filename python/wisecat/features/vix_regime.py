"""VIX-based regime features.

VIX history comes from `context.vix_history` (a daily OHLCV-shaped frame
with a `close` column for ^VIX). Trend strategies that work in calm
regimes lose money when VIX > 25 — exposing VIX as a feature lets the
GBM learn that conditioning instead of forcing two separate models.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import pandas as pd

if TYPE_CHECKING:
    from . import FeatureContext


_LOOKBACK_CHANGE = 21
_LOOKBACK_ZSCORE = 252
_ZSCORE_CAP = 5.0


def compute(df: pd.DataFrame, context: "FeatureContext") -> dict[str, float]:
    vix = getattr(context, "vix_history", None)
    if vix is None or len(vix) == 0 or "close" not in vix.columns:
        return {}

    vix_sorted = vix.sort_values("date").reset_index(drop=True) if "date" in vix.columns else vix.reset_index(drop=True)
    closes = vix_sorted["close"].astype(float)
    if len(closes) == 0:
        return {}

    out: dict[str, float] = {}

    last = closes.iloc[-1]
    if not pd.isna(last):
        out["vix_level"] = float(last)

    if len(closes) >= _LOOKBACK_CHANGE + 1:
        prior = closes.iloc[-1 - _LOOKBACK_CHANGE]
        if not pd.isna(prior) and not pd.isna(last):
            out["vix_change_21d"] = float(last - prior)

    if len(closes) >= _LOOKBACK_ZSCORE:
        window = closes.iloc[-_LOOKBACK_ZSCORE:]
        mean = float(window.mean())
        std = float(window.std(ddof=0))
        if std > 0 and not pd.isna(last):
            z = (float(last) - mean) / std
            if not pd.isna(z):
                out["vix_zscore_252d"] = float(max(-_ZSCORE_CAP, min(_ZSCORE_CAP, z)))

    return out
