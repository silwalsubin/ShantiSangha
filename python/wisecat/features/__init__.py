"""Feature computation for the LightGBM scoring pipeline.

Each feature module exposes a `compute(df, context) -> dict[str, float]`
that returns a flat name -> value mapping. `compute_all_features()` is the
single entry point that fans out to every registered module and merges
their outputs into one row.

`FeatureContext` carries shared resources (SPY history, VIX history,
sector map, etc.) that several features need, loaded once per scoring
batch instead of per ticker. Per-ticker bars are passed through `df`.
"""

from dataclasses import dataclass, field
from datetime import date
import pandas as pd


@dataclass
class FeatureContext:
    """Shared resources loaded once per scoring batch.

    Per-ticker features pull what they need from this context (e.g.
    cross-sectional features need SPY history, regime features need VIX).
    Loaded once per batch instead of re-fetching per ticker.
    """
    spy_history: pd.DataFrame | None = None
    vix_history: pd.DataFrame | None = None
    earnings_dates: dict[str, list[date]] = field(default_factory=dict)
    sector_map: dict[str, str] = field(default_factory=dict)
    macro: dict[str, pd.DataFrame] = field(default_factory=dict)


def compute_all_features(
    ticker: str,
    df: pd.DataFrame,
    context: FeatureContext,
) -> dict[str, float]:
    """Compute every registered feature for one (ticker, df) pair.

    Returns a flat dict of feature_name -> float in deterministic order.
    Modules that lack the data they need (e.g. earnings without
    `context.earnings_dates[ticker]`) return an empty dict — those keys
    are simply absent and the training pipeline fills NaN with 0.0.
    """
    from . import (
        base_technicals,
        calendar,
        cross_sectional,
        earnings,
        range_position,
        vix_regime,
    )

    # earnings.compute() resolves the ticker via df.attrs["ticker"] —
    # set it here so the call stays a clean (df, context) signature.
    if hasattr(df, "attrs"):
        df.attrs["ticker"] = ticker

    out: dict[str, float] = {}
    out.update(base_technicals.compute(df, context))
    out.update(cross_sectional.compute(df, context))
    out.update(earnings.compute(df, context))
    out.update(calendar.compute(df, context))
    out.update(range_position.compute(df, context))
    out.update(vix_regime.compute(df, context))
    return out
