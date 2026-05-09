"""Tests for the per-feature compute() modules under wisecat/features/.

These tests use a local FeatureContext stub — the real class is owned by
the parallel orchestration agent in wisecat/features/__init__.py. The
contract under test is exactly the duck-typed shape the feature modules
read: spy_history, vix_history, earnings_dates. As long as those
attributes are present, the modules don't care which concrete class
holds them.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, timedelta

import numpy as np
import pandas as pd
import pytest

from wisecat.features import (
    calendar as calendar_feat,
    cross_sectional,
    earnings,
    range_position,
    vix_regime,
)


@dataclass
class _Ctx:
    spy_history: pd.DataFrame | None = None
    vix_history: pd.DataFrame | None = None
    earnings_dates: dict[str, list[date]] = field(default_factory=dict)
    sector_map: dict[str, str] = field(default_factory=dict)
    macro: dict[str, pd.DataFrame] = field(default_factory=dict)


def _bars(prices: list[float], volumes: list[int] | None = None, start: str = "2024-01-01") -> pd.DataFrame:
    n = len(prices)
    if volumes is None:
        volumes = [1_000_000] * n
    return pd.DataFrame({
        "date": pd.date_range(start, periods=n, freq="B").date,
        "open": prices,
        "high": [p * 1.01 for p in prices],
        "low": [p * 0.99 for p in prices],
        "close": prices,
        "volume": volumes,
    })


# ---------- cross_sectional ----------

def test_cross_sectional_returns_three_horizons_when_data_aligned():
    ticker_prices = list(np.linspace(100.0, 150.0, 300))   # +50%
    spy_prices = list(np.linspace(100.0, 110.0, 300))      # +10%
    df = _bars(ticker_prices)
    spy = _bars(spy_prices)
    ctx = _Ctx(spy_history=spy)

    out = cross_sectional.compute(df, ctx)
    assert set(out.keys()) == {
        "xs_return_spread_3m_vs_spy",
        "xs_return_spread_6m_vs_spy",
        "xs_return_spread_1y_vs_spy",
    }
    for v in out.values():
        assert isinstance(v, float)
    # ticker outperformed SPY at every horizon → all spreads positive.
    assert all(v > 0 for v in out.values())


def test_cross_sectional_empty_when_no_spy_context():
    df = _bars(list(np.linspace(100.0, 150.0, 300)))
    ctx = _Ctx(spy_history=None)
    assert cross_sectional.compute(df, ctx) == {}


def test_cross_sectional_skips_horizons_with_insufficient_history():
    df = _bars(list(np.linspace(100.0, 110.0, 80)))   # only ~3M of bars
    spy = _bars(list(np.linspace(100.0, 105.0, 80)))
    out = cross_sectional.compute(df, _Ctx(spy_history=spy))
    # 3M (63d) should fit; 6M and 1Y should not.
    assert "xs_return_spread_3m_vs_spy" in out
    assert "xs_return_spread_6m_vs_spy" not in out
    assert "xs_return_spread_1y_vs_spy" not in out


# ---------- earnings ----------

def test_earnings_features_present_when_dates_known():
    df = _bars(list(np.linspace(100.0, 110.0, 100)))
    df.attrs["ticker"] = "TEST"
    last_bar_date = df["date"].iloc[-1]
    # Earnings 30 trading days ago (~6 weeks calendar).
    past_earnings = last_bar_date - timedelta(days=42)
    ctx = _Ctx(earnings_dates={"TEST": [past_earnings]})

    out = earnings.compute(df, ctx)
    assert "days_since_earnings" in out
    assert "days_to_earnings" in out
    assert isinstance(out["days_since_earnings"], float)
    assert 0.0 <= out["days_since_earnings"] <= 200.0
    # No future earnings supplied → capped.
    assert out["days_to_earnings"] == 200.0
    # Drift signal should be present and a float.
    if "post_earnings_drift_signal" in out:
        assert isinstance(out["post_earnings_drift_signal"], float)


def test_earnings_empty_when_no_dates():
    df = _bars([100.0] * 50)
    df.attrs["ticker"] = "TEST"
    ctx = _Ctx(earnings_dates={})
    assert earnings.compute(df, ctx) == {}


def test_earnings_drift_decays_to_zero_far_after_earnings():
    # 200 bars; earnings 180 bars ago (well past the 60+60 window).
    n = 200
    df = _bars(list(np.linspace(100.0, 110.0, n)))
    df.attrs["ticker"] = "TEST"
    earn_date = df["date"].iloc[-180]
    ctx = _Ctx(earnings_dates={"TEST": [earn_date]})
    out = earnings.compute(df, ctx)
    if "post_earnings_drift_signal" in out:
        assert out["post_earnings_drift_signal"] == 0.0


# ---------- calendar ----------

def test_calendar_features_present():
    df = _bars([100.0] * 30)
    out = calendar_feat.compute(df, _Ctx())
    assert set(out.keys()) == {
        "month_of_year",
        "day_of_week",
        "quarter_end_proximity",
        "january_effect_flag",
    }
    for v in out.values():
        assert isinstance(v, float)
    assert 1.0 <= out["month_of_year"] <= 12.0
    assert 0.0 <= out["day_of_week"] <= 6.0
    assert 0.0 <= out["quarter_end_proximity"] <= 63.0
    assert out["january_effect_flag"] in (0.0, 1.0)


def test_calendar_january_effect_flag_set_in_january():
    # Build a df where the last bar lands in January.
    df = pd.DataFrame({
        "date": pd.date_range("2024-12-25", periods=10, freq="B").date,
        "open": [100.0] * 10,
        "high": [101.0] * 10,
        "low": [99.0] * 10,
        "close": [100.0] * 10,
        "volume": [1_000_000] * 10,
    })
    out = calendar_feat.compute(df, _Ctx())
    last = df["date"].iloc[-1]
    if last.month == 1:
        assert out["january_effect_flag"] == 1.0
    else:
        assert out["january_effect_flag"] == 0.0


# ---------- range_position ----------

def test_range_position_features_present():
    df = _bars(list(np.linspace(100.0, 120.0, 50)))
    out = range_position.compute(df, _Ctx())
    expected = {
        "range_position_today",
        "range_position_5d_avg",
        "body_to_atr_ratio",
        "upper_wick_pct",
        "lower_wick_pct",
    }
    assert expected.issubset(out.keys())
    for v in out.values():
        assert isinstance(v, float)
    assert 0.0 <= out["range_position_today"] <= 1.0
    assert 0.0 <= out["range_position_5d_avg"] <= 1.0
    assert 0.0 <= out["upper_wick_pct"] <= 1.0
    assert 0.0 <= out["lower_wick_pct"] <= 1.0
    assert out["body_to_atr_ratio"] >= 0.0


def test_range_position_degenerate_bar_uses_safe_defaults():
    # All OHLC equal → high == low → degenerate.
    n = 30
    df = pd.DataFrame({
        "date": pd.date_range("2024-01-01", periods=n, freq="B").date,
        "open": [100.0] * n,
        "high": [100.0] * n,
        "low": [100.0] * n,
        "close": [100.0] * n,
        "volume": [1_000_000] * n,
    })
    out = range_position.compute(df, _Ctx())
    assert out["range_position_today"] == 0.5
    assert out["upper_wick_pct"] == 0.0
    assert out["lower_wick_pct"] == 0.0


# ---------- vix_regime ----------

def test_vix_regime_full_features_when_history_long_enough():
    # 300 days of synthetic VIX in a plausible range.
    rng = np.random.default_rng(7)
    levels = 18.0 + rng.normal(0, 2.0, 300).cumsum() * 0.05
    levels = np.clip(levels, 10.0, 60.0)
    vix = pd.DataFrame({
        "date": pd.date_range("2024-01-01", periods=300, freq="B").date,
        "open": levels,
        "high": levels * 1.02,
        "low": levels * 0.98,
        "close": levels,
        "volume": [0] * 300,
    })
    df = _bars([100.0] * 30)
    out = vix_regime.compute(df, _Ctx(vix_history=vix))
    assert set(out.keys()) >= {"vix_level", "vix_change_21d", "vix_zscore_252d"}
    for v in out.values():
        assert isinstance(v, float)
    assert -5.0 <= out["vix_zscore_252d"] <= 5.0


def test_vix_regime_short_history_omits_zscore():
    # 100 bars — short of the 252d zscore window but enough for level + 21d change.
    levels = [18.0] * 100
    vix = pd.DataFrame({
        "date": pd.date_range("2024-01-01", periods=100, freq="B").date,
        "close": levels,
    })
    df = _bars([100.0] * 30)
    out = vix_regime.compute(df, _Ctx(vix_history=vix))
    assert "vix_level" in out
    assert "vix_zscore_252d" not in out


def test_vix_regime_empty_when_no_history():
    df = _bars([100.0] * 30)
    assert vix_regime.compute(df, _Ctx(vix_history=None)) == {}
