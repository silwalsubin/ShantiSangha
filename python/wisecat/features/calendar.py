"""Pure date-math features off the latest bar.

No external context required. Months/days are emitted as floats so the
GBM training pipeline can treat them as either categorical bins or
continuous sinusoids downstream.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import TYPE_CHECKING

import pandas as pd

if TYPE_CHECKING:
    from . import FeatureContext


_QUARTER_END_MONTHS = (3, 6, 9, 12)
_MAX_QUARTER_END_DISTANCE = 63.0


def _last_business_day(year: int, month: int) -> date:
    if month == 12:
        d = date(year + 1, 1, 1) - timedelta(days=1)
    else:
        d = date(year, month + 1, 1) - timedelta(days=1)
    # weekday: Mon=0 ... Sun=6. Walk back to Friday if needed.
    while d.weekday() >= 5:
        d -= timedelta(days=1)
    return d


def _trading_days_between(start: date, end: date) -> int:
    """Approximate count of business days between start and end (end exclusive)."""
    if end <= start:
        return 0
    # pandas bdate_range counts business days inclusive; subtract 1 to keep end exclusive.
    rng = pd.bdate_range(start=start, end=end)
    # bdate_range includes both endpoints when they fall on business days; we want
    # the gap, so just take the length minus 1 if start is in range, else length.
    n = len(rng)
    if n == 0:
        return 0
    if rng[0].date() == start:
        return max(0, n - 1)
    return n


def _next_quarter_end(today: date) -> date:
    candidates: list[date] = []
    for m in _QUARTER_END_MONTHS:
        if m >= today.month:
            candidates.append(_last_business_day(today.year, m))
    candidates.append(_last_business_day(today.year + 1, _QUARTER_END_MONTHS[0]))
    for c in candidates:
        if c >= today:
            return c
    return candidates[-1]


def compute(df: pd.DataFrame, context: "FeatureContext") -> dict[str, float]:
    if len(df) == 0 or "date" not in df.columns:
        return {}
    df_sorted = df.sort_values("date").reset_index(drop=True)
    today = df_sorted["date"].iloc[-1]
    if not isinstance(today, date):
        try:
            today = pd.to_datetime(today).date()
        except (TypeError, ValueError):
            return {}

    out: dict[str, float] = {
        "month_of_year": float(today.month),
        "day_of_week": float(today.weekday()),  # Mon=0..Sun=6
        "january_effect_flag": 1.0 if today.month == 1 else 0.0,
    }

    nq = _next_quarter_end(today)
    distance = _trading_days_between(today, nq)
    out["quarter_end_proximity"] = float(min(_MAX_QUARTER_END_DISTANCE, max(0.0, distance)))

    return out
