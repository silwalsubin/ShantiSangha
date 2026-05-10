"""Tests for the Lambda dispatch entry points.

The Lambda is invoked by the .NET task with bars serialized over JSON, so the
`date` column arrives as strings. Several feature modules (earnings,
cross_sectional, vix_regime) compare those values to `datetime.date`
instances loaded from the parquet `FeatureContext`. Without an explicit
normalize step the comparison raises TypeError, scoring catches it, and
every horizon falls back to the neutral verdict (pHold=1.0). That looks
like "no probability bar" on the iOS detail view.

This test guards the normalize step in `_score` so the regression doesn't
recur.
"""

from __future__ import annotations

from datetime import date, timedelta

import numpy as np
import pandas as pd
import pytest


def _make_bars(n: int = 400) -> list[dict]:
    """Build a list of synthetic OHLCV bars with ISO-string dates — exactly
    the shape `marketData.ScoreAsync()` sends from .NET."""
    end = date(2026, 5, 8)
    rng = np.random.default_rng(seed=42)
    closes = 100.0 + np.cumsum(rng.normal(0.05, 1.0, size=n))
    bars = []
    for i, close in enumerate(closes):
        d = end - timedelta(days=(n - 1 - i))
        bars.append({
            "date": d.isoformat(),
            "open": float(close - 0.2),
            "high": float(close + 0.5),
            "low": float(close - 0.5),
            "close": float(close),
            "volume": 1_000_000 + i * 100,
        })
    return bars


def test_score_handles_iso_string_dates() -> None:
    """JSON bars -> _score must normalize date strings to datetime.date so
    feature modules don't blow up on cross-type comparisons."""
    from wisecat.lambda_handler import _score

    bars = _make_bars()
    event = {"items": [{"ticker": "AAPL", "bars": bars, "price": 150.0}]}
    out = _score(event)

    assert "scores" in out and len(out["scores"]) == 1
    horizons = out["scores"][0]["horizons"]
    assert set(horizons.keys()) == {"1W", "1M", "1Y"}

    # GBM artifacts ship in-tree (committed, not gitignored) so they're
    # present in CI too. With JSON-string dates fixed in `_score`, every
    # horizon should run GBM and emit a non-degenerate distribution. The
    # exact original regression: pHold=1.0 / pBuy=pSell=0 for every horizon
    # because feature compute raised TypeError and got swallowed.
    for h, score in horizons.items():
        total = score["pBuy"] + score["pHold"] + score["pSell"]
        assert 0.99 <= total <= 1.01, f"{h} probabilities don't sum to 1: {score}"
        non_degenerate = score["pBuy"] > 0 or score["pSell"] > 0
        assert non_degenerate, (
            f"{h} fell back to the neutral degenerate verdict — string-date "
            f"normalization regressed in _score: {score}"
        )
