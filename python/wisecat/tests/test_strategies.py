import numpy as np
import pandas as pd
import pytest

from wisecat.strategies import ALL_STRATEGIES
from wisecat.strategies.mean_reversion import score as mr_score
from wisecat.strategies.momentum import score as mom_score
from wisecat.strategies.trend import score as trend_score
from wisecat.strategies.volume import score as vol_score


def _bars(prices: list[float], volumes: list[int] | None = None) -> pd.DataFrame:
    n = len(prices)
    if volumes is None:
        volumes = [1_000_000] * n
    return pd.DataFrame({
        "date": pd.date_range("2024-01-01", periods=n, freq="B").date,
        "open": prices,
        "high": [p * 1.01 for p in prices],
        "low": [p * 0.99 for p in prices],
        "close": prices,
        "volume": volumes,
    })


def test_short_history_returns_neutral():
    df = _bars([100.0] * 10)
    for _, fn in ALL_STRATEGIES:
        raw, value = fn(df)
        assert value == 0.0


def test_trend_uptrend_is_positive():
    prices = list(np.linspace(100, 200, 250))
    df = _bars(prices)
    _, value = trend_score(df)
    assert value > 0.5


def test_trend_downtrend_is_negative():
    prices = list(np.linspace(200, 100, 250))
    df = _bars(prices)
    _, value = trend_score(df)
    assert value < -0.5


def test_momentum_oversold_is_positive():
    prices = list(np.linspace(200, 100, 60))
    df = _bars(prices)
    _, value = mom_score(df)
    assert value > 0


def test_momentum_overbought_is_negative():
    prices = list(np.linspace(100, 200, 60))
    df = _bars(prices)
    _, value = mom_score(df)
    assert value < 0


def test_mean_reversion_above_band_is_negative():
    base = [100.0] * 30
    base[-1] = 130.0
    df = _bars(base)
    _, value = mr_score(df)
    assert value < 0


def test_mean_reversion_below_band_is_positive():
    base = [100.0] * 30
    base[-1] = 70.0
    df = _bars(base)
    _, value = mr_score(df)
    assert value > 0


def test_volume_confirm_up_day_high_volume_is_positive():
    prices = [100.0] * 20 + [105.0]
    volumes = [1_000_000] * 20 + [5_000_000]
    df = _bars(prices, volumes)
    _, value = vol_score(df)
    assert value > 0


def test_volume_confirm_down_day_high_volume_is_negative():
    prices = [100.0] * 20 + [95.0]
    volumes = [1_000_000] * 20 + [5_000_000]
    df = _bars(prices, volumes)
    _, value = vol_score(df)
    assert value < 0
