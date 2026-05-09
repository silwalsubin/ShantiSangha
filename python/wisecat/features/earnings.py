"""Earnings-event awareness — days-since/days-to and post-earnings drift.

Per-ticker earnings dates come from `context.earnings_dates[ticker]`. We
also need a way to identify the ticker from the dataframe, but the
dataframe doesn't carry it; the orchestration layer is expected to call
`compute()` once per ticker with its own slice of the lookup. We accept
a `ticker` attribute on `df.attrs` if present, otherwise we inspect the
context for a single-ticker earnings_dates and use that. The
orchestration agent owns wiring this — we keep both shapes working.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import TYPE_CHECKING

import pandas as pd

if TYPE_CHECKING:
    from . import FeatureContext


_CAP = 200.0
_DRIFT_HOLD_DAYS = 60
_DRIFT_DECAY_DAYS = 60


def _resolve_dates(df: pd.DataFrame, context: "FeatureContext") -> list[date]:
    earnings = getattr(context, "earnings_dates", None) or {}
    ticker = df.attrs.get("ticker") if hasattr(df, "attrs") else None
    if ticker and ticker in earnings:
        return list(earnings[ticker])
    # Single-ticker convenience: if the lookup carries exactly one entry,
    # assume that's us.
    if len(earnings) == 1:
        return list(next(iter(earnings.values())))
    return []


def _trading_days_between(df: pd.DataFrame, anchor: date, target: date) -> int | None:
    """Count trading bars in df between anchor and target (inclusive of
    target side). Returns None if either bound is outside df.
    """
    dates = df["date"].tolist()
    if anchor not in dates and target not in dates:
        # neither matches a bar — fall back to calendar approximation
        days = abs((target - anchor).days)
        return int(round(days * 5 / 7))
    try:
        if anchor in dates and target in dates:
            i = dates.index(anchor)
            j = dates.index(target)
            return abs(j - i)
        # Otherwise, the side that's in dates is exact; the missing side
        # we approximate by counting bars in df with date < or > the missing
        # side.
        if target in dates:
            j = dates.index(target)
            n_before = sum(1 for d in dates if d <= anchor)
            return abs(j - (n_before - 1))
        if anchor in dates:
            i = dates.index(anchor)
            n_before = sum(1 for d in dates if d <= target)
            return abs(i - (n_before - 1))
    except ValueError:
        pass
    days = abs((target - anchor).days)
    return int(round(days * 5 / 7))


def compute(df: pd.DataFrame, context: "FeatureContext") -> dict[str, float]:
    if len(df) == 0 or "date" not in df.columns:
        return {}
    earn_dates = _resolve_dates(df, context)
    if not earn_dates:
        return {}

    df_sorted = df.sort_values("date").reset_index(drop=True)
    today = df_sorted["date"].iloc[-1]

    past = sorted([d for d in earn_dates if d <= today])
    future = sorted([d for d in earn_dates if d > today])

    out: dict[str, float] = {}

    if past:
        last = past[-1]
        days_since = _trading_days_between(df_sorted, today, last)
        if days_since is None:
            days_since = 0
        out["days_since_earnings"] = float(min(_CAP, max(0.0, days_since)))
    else:
        out["days_since_earnings"] = float(_CAP)

    if future:
        nxt = future[0]
        days_to = _trading_days_between(df_sorted, today, nxt)
        if days_to is None:
            days_to = int(_CAP)
        out["days_to_earnings"] = float(min(_CAP, max(0.0, days_to)))
    else:
        out["days_to_earnings"] = float(_CAP)

    # Post-earnings drift: 1-day reaction at the most recent earnings,
    # decayed linearly to 0 over the 60d window after a 60d hold.
    if past:
        last = past[-1]
        dates = df_sorted["date"].tolist()
        # Find the bar at-or-after `last` (earnings often hit AMC and the
        # reaction is the next day's close).
        reaction_idx: int | None = None
        for i, d in enumerate(dates):
            if d >= last:
                reaction_idx = i
                break
        if reaction_idx is not None and reaction_idx >= 1:
            try:
                close_after = float(df_sorted["close"].iloc[reaction_idx])
                close_prior = float(df_sorted["close"].iloc[reaction_idx - 1])
            except (IndexError, ValueError):
                close_after = close_prior = 0.0
            if close_prior > 0 and not pd.isna(close_after) and not pd.isna(close_prior):
                reaction = close_after / close_prior - 1.0
                bars_since = len(dates) - 1 - reaction_idx
                if bars_since <= _DRIFT_HOLD_DAYS:
                    decay = 1.0
                elif bars_since <= _DRIFT_HOLD_DAYS + _DRIFT_DECAY_DAYS:
                    decay = 1.0 - (bars_since - _DRIFT_HOLD_DAYS) / _DRIFT_DECAY_DAYS
                else:
                    decay = 0.0
                drift = reaction * decay
                if not pd.isna(drift):
                    out["post_earnings_drift_signal"] = float(drift)

    return out
