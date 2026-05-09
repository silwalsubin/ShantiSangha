"""Smoke test for the GBM training infrastructure.

Verifies the dataset/builder/training contract end-to-end on a synthetic
3-ticker basket — no network calls, no real model quality assertions.
We only check shapes, label encoding, and artifact keys.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from wisecat.train import (
    LABEL_BUY,
    LABEL_HOLD,
    LABEL_SELL,
    build_dataset,
    save_model_artifact,
    train_one_horizon,
)


def _bars(prices: list[float], volumes: list[int] | None = None) -> pd.DataFrame:
    n = len(prices)
    if volumes is None:
        volumes = [1_000_000] * n
    return pd.DataFrame({
        "date": pd.date_range("2020-01-01", periods=n, freq="B").date,
        "open": prices,
        "high": [p * 1.01 for p in prices],
        "low": [p * 0.99 for p in prices],
        "close": prices,
        "volume": volumes,
    })


def _synthetic_histories(seed: int = 7) -> dict[str, pd.DataFrame]:
    """Three fake tickers, 600 bars each. Different drifts so the labels
    span all three classes (buy / hold / sell)."""
    rng = np.random.default_rng(seed)
    out: dict[str, pd.DataFrame] = {}

    n = 600
    # AAA: steady uptrend → many forward returns ≥ +5% (Buy at 1M).
    aaa = list(np.linspace(50.0, 200.0, n) + rng.normal(0, 0.5, n).cumsum() * 0.1)
    out["AAA"] = _bars(aaa)
    # BBB: steady downtrend → Sell labels.
    bbb = list(np.linspace(200.0, 50.0, n) + rng.normal(0, 0.5, n).cumsum() * 0.1)
    out["BBB"] = _bars(bbb)
    # CCC: flat with noise → mostly Hold.
    ccc = list(100.0 + rng.normal(0, 0.5, n).cumsum() * 0.05)
    out["CCC"] = _bars(ccc)
    return out


def test_build_dataset_shape_and_labels():
    histories = _synthetic_histories()
    X, y, dates = build_dataset(
        ["AAA", "BBB", "CCC"],
        horizon="1M",
        histories=histories,
        allow_network=False,
    )

    # Shape — same row count across all three.
    assert len(X) == len(y) == len(dates)
    assert len(X) > 0

    # Feature columns: every base technical strategy emits raw + value.
    expected_cols = {
        "trend_50_200_raw", "trend_50_200_value",
        "ts_momentum_12_1_raw", "ts_momentum_12_1_value",
        "fast_trend_5_20_raw", "fast_trend_5_20_value",
    }
    assert expected_cols.issubset(set(X.columns))

    # Labels strictly in {0, 1, 2}.
    label_set = set(int(v) for v in np.unique(y))
    assert label_set.issubset({LABEL_SELL, LABEL_HOLD, LABEL_BUY})

    # Dates align with feature rows and are datetime64.
    assert dates.dtype.kind == "M"


def test_train_one_horizon_artifact_keys(tmp_path):
    histories = _synthetic_histories()
    X, y, dates = build_dataset(
        ["AAA", "BBB", "CCC"],
        horizon="1M",
        histories=histories,
        allow_network=False,
    )

    # Synthetic basket gives only ~900 unique dates; shrink the CV
    # windows so we get a couple of folds without needing real-scale data.
    artifact = train_one_horizon(
        X, y, dates,
        horizon="1M",
        train_window=200,
        eval_window=50,
        embargo=21,
    )

    # Required keys per spec.
    for key in ("model", "features", "label_thresholds", "trained_at"):
        assert key in artifact, f"missing key: {key}"

    # Feature list matches dataset columns and order.
    assert artifact["features"] == list(X.columns)

    # Thresholds carry both buy and sell.
    assert {"buy", "sell"}.issubset(artifact["label_thresholds"].keys())

    # CV ran at least once.
    assert artifact["cv"]["n_folds"] >= 1

    # Persistence round-trips without exploding.
    out = save_model_artifact(artifact, tmp_path / "gbm_1M.joblib")
    assert out.exists()
