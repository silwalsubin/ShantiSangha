import numpy as np
import pandas as pd
import pytest

from wisecat.scoring import score_ticker
from wisecat.strategies import (
    ALL_STRATEGIES,
    HORIZONS,
    STRATEGY_WEIGHTS_BY_HORIZON,
)
# mean_reversion / momentum / volume strategies are still in the source
# tree but unregistered after the 2026-05-07 basket tune showed sub-coinflip
# hit rate. Their unit tests still run against the strategy files directly.
from wisecat.strategies.mean_reversion import score as mr_score
from wisecat.strategies.momentum import score as mom_score
from wisecat.strategies.trend import score as trend_score
from wisecat.strategies.ts_momentum import score as ts_mom_score
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


def test_ts_momentum_short_history_is_neutral():
    prices = list(np.linspace(100, 200, 200))
    df = _bars(prices)
    _, value = ts_mom_score(df)
    assert value == 0.0


def test_ts_momentum_uptrend_is_positive():
    # 300 bars, +50% over the trailing year.
    prices = list(np.linspace(100, 150, 300))
    df = _bars(prices)
    raw, value = ts_mom_score(df)
    assert raw > 0
    assert value > 0.5


def test_ts_momentum_downtrend_is_negative():
    prices = list(np.linspace(200, 120, 300))
    df = _bars(prices)
    raw, value = ts_mom_score(df)
    assert raw < 0
    assert value < -0.5


def test_ts_momentum_skips_recent_month():
    # 12-1 momentum should be DRIVEN BY the year ending 21 days ago, NOT by
    # the most recent month. Build a series with steady gains for 12 months
    # then a sharp crash in the last month — score should still be positive.
    base = list(np.linspace(100, 150, 280))
    crash = [150 * 0.7] * 21  # 30% crash in last month
    df = _bars(base + crash)
    _, value = ts_mom_score(df)
    assert value > 0  # crash was in the skipped window; trailing year is +50%


def test_per_horizon_weights_sum_to_one():
    for horizon, weights in STRATEGY_WEIGHTS_BY_HORIZON.items():
        total = sum(weights.values())
        assert abs(total - 1.0) < 1e-9, f"{horizon} weights sum to {total}"


def test_per_horizon_weights_cover_all_strategies():
    strategy_names = {name for name, _ in ALL_STRATEGIES}
    for horizon, weights in STRATEGY_WEIGHTS_BY_HORIZON.items():
        missing = strategy_names - set(weights.keys())
        assert not missing, f"{horizon} missing weights for {missing}"


def test_score_ticker_returns_per_horizon_scores():
    # Strong uptrend so trend + 12-1 dominate at 1Y; oscillators saturate at 1W.
    rng = np.random.default_rng(seed=11)
    base = np.linspace(100.0, 200.0, 300)
    noise = rng.normal(0, 0.5, 300).cumsum()
    df = _bars(list(base + noise))

    score = score_ticker("TEST", df, price=float(df["close"].iloc[-1]))
    assert set(score.horizons.keys()) == set(HORIZONS)
    for horizon in HORIZONS:
        hs = score.horizons[horizon]
        assert -1.0 <= hs.score <= 1.0
        # Every strategy should appear in every horizon's signal list (even
        # when its weight is 0 — preserves the contract for the iOS detail view).
        names_present = {sig.name for sig in hs.signals}
        names_expected = {name for name, _ in ALL_STRATEGIES}
        assert names_present == names_expected


def test_score_ticker_horizon_weights_differ():
    # Same raw signal should produce different contributions at different horizons.
    # With the post-2026-05-07 weights, trend is 0.55 at 1Y, 0.45 at 1W, 0.50
    # at 1M — not the wild differentials of the v1 stack, but still distinct.
    prices = list(np.linspace(100.0, 200.0, 300))
    df = _bars(prices)
    score = score_ticker("TEST", df, price=200.0)

    one_y_trend = next(s.contribution for s in score.horizons["1Y"].signals if s.name == "trend_50_200")
    one_w_trend = next(s.contribution for s in score.horizons["1W"].signals if s.name == "trend_50_200")
    one_y_tsmom = next(s.contribution for s in score.horizons["1Y"].signals if s.name == "ts_momentum_12_1")
    one_w_tsmom = next(s.contribution for s in score.horizons["1W"].signals if s.name == "ts_momentum_12_1")

    # 1Y trend weight (0.55) > 1W trend weight (0.45) → bigger 1Y contribution.
    assert one_y_trend > one_w_trend
    # 1W ts_momentum weight (0.55) > 1Y ts_momentum weight (0.45) → opposite tilt.
    assert one_w_tsmom > one_y_tsmom
