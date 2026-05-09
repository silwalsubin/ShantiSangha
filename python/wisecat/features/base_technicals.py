"""Wrap the existing trend/momentum strategies as GBM features.

Each strategy returns `(raw, value)` — we emit BOTH so the GBM has access
to the unsaturated raw gap (better for splits) and the saturated [-1, 1]
score (matches the legacy weighted-sum view). NaN or exception falls
back to 0.0 so the GBM never sees missing values from this module.
"""

from __future__ import annotations

import math

import pandas as pd

from . import FeatureContext
from ..strategies.fast_trend import score as fast_trend_score
from ..strategies.trend import score as trend_score
from ..strategies.ts_momentum import score as ts_momentum_score


# Order matters only insofar as `compute_all_features` returns a stable
# dict — Python 3.7+ dicts preserve insertion order, so the column order
# fed to LightGBM is deterministic across runs.
_BASE_STRATEGIES: tuple[tuple[str, callable], ...] = (
    ("trend_50_200", trend_score),
    ("ts_momentum_12_1", ts_momentum_score),
    ("fast_trend_5_20", fast_trend_score),
)


def _safe_float(x: float) -> float:
    if x is None:
        return 0.0
    try:
        if math.isnan(x) or math.isinf(x):
            return 0.0
    except TypeError:
        return 0.0
    return float(x)


def compute(df: pd.DataFrame, context: FeatureContext) -> dict[str, float]:
    """Run each base strategy once and emit raw + saturated value as two
    features per strategy. NaN / exception → 0.0."""
    out: dict[str, float] = {}
    for name, fn in _BASE_STRATEGIES:
        try:
            raw, value = fn(df)
        except Exception:
            raw, value = 0.0, 0.0
        out[f"{name}_raw"] = _safe_float(raw)
        out[f"{name}_value"] = _safe_float(value)
    return out
