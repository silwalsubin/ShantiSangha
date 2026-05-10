"""Regression test for GBM per-feature contribution signals.

For each horizon with a model artifact on disk, the scoring path must
populate `HorizonScore.signals` with the top-8 per-feature contributions
from LightGBM's built-in `pred_contrib`. This is what the iOS detail view
reads to show "why" behind the verdict — without it the per-feature
breakdown is hidden.
"""

from __future__ import annotations

from datetime import date, timedelta
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import pytest


def _make_bars(n: int = 400) -> pd.DataFrame:
    """Synthetic OHLCV — same shape as `test_lambda_handler._make_bars`,
    but already a DataFrame because `score_ticker` consumes one directly."""
    end = date(2026, 5, 8)
    rng = np.random.default_rng(seed=42)
    closes = 100.0 + np.cumsum(rng.normal(0.05, 1.0, size=n))
    rows = []
    for i, close in enumerate(closes):
        d = end - timedelta(days=(n - 1 - i))
        rows.append({
            "date": d,
            "open": float(close - 0.2),
            "high": float(close + 0.5),
            "low": float(close - 0.5),
            "close": float(close),
            "volume": 1_000_000 + i * 100,
        })
    return pd.DataFrame(rows)


def test_gbm_signals_populated() -> None:
    """For each horizon with an artifact on disk, every HorizonScore
    must carry a non-empty, sensibly-shaped `signals` list."""
    from wisecat.features import FeatureContext
    from wisecat.scoring import score_ticker

    df = _make_bars()
    ctx = FeatureContext()

    result = score_ticker("AAPL", df, price=150.0, context=ctx)

    # All three horizons should be present.
    assert set(result.horizons.keys()) == {"1W", "1M", "1Y"}

    # Pre-load the artifacts to assert feature names are real.
    models_dir = Path(__file__).resolve().parent.parent / "models"
    artifacts: dict[str, dict] = {}
    for h in ("1W", "1M", "1Y"):
        path = models_dir / f"gbm_{h}.joblib"
        if path.exists():
            artifacts[h] = joblib.load(path)

    # If no artifacts are present (unlikely — they're committed), nothing
    # to assert. Horizons without artifacts emit a neutral verdict.
    if not artifacts:
        pytest.skip("no GBM artifacts on disk; nothing to assert")

    for horizon, artifact in artifacts.items():
        feature_names = set(artifact["features"])
        score = result.horizons[horizon]
        signals = score.signals

        # Non-empty and capped at 8.
        assert len(signals) > 0, f"{horizon}: signals empty"
        assert len(signals) <= 8, f"{horizon}: signals exceeds 8 ({len(signals)})"

        # Weights sum to ~1.0 within the displayed top-K slice.
        total_weight = sum(s.weight for s in signals)
        assert 0.99 <= total_weight <= 1.01, (
            f"{horizon}: weights don't sum to ~1.0 (got {total_weight}): "
            f"{[(s.name, s.weight) for s in signals]}"
        )

        # Contributions are signed (some non-zero magnitude expected).
        magnitudes = [abs(s.contribution) for s in signals]
        assert max(magnitudes) > 0.0, f"{horizon}: every contribution is zero"

        # Every feature name surfaced must come from the trained artifact.
        for s in signals:
            assert s.name in feature_names, (
                f"{horizon}: surfaced feature {s.name!r} not in artifact "
                f"feature list {sorted(feature_names)}"
            )

        # Top-K ordering: |contributions| should be non-increasing.
        for a, b in zip(magnitudes, magnitudes[1:]):
            assert a + 1e-9 >= b, (
                f"{horizon}: signals not ordered by |contribution|: "
                f"{magnitudes}"
            )
