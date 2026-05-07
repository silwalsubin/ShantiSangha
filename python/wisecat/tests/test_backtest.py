import numpy as np
import pandas as pd
import pytest

from wisecat.backtest import run_backtest


def _synthetic_history(prices: list[float]) -> pd.DataFrame:
    n = len(prices)
    return pd.DataFrame({
        "date": pd.date_range("2020-01-01", periods=n, freq="B").date,
        "open": prices,
        "high": [p * 1.005 for p in prices],
        "low": [p * 0.995 for p in prices],
        "close": prices,
        "volume": [1_000_000] * n,
    })


def test_run_backtest_runs_end_to_end():
    # Trend with realistic noise so per-strategy contributions don't all
    # saturate at extremes (perfectly linear prices push RSI to 100 and
    # Bollinger %B to the upper band, drowning out everything else).
    rng = np.random.default_rng(seed=42)
    base = np.linspace(100.0, 160.0, 600)
    noise = rng.normal(0, 1.5, 600).cumsum()
    prices = list(base + noise)
    df = _synthetic_history(prices)

    result = run_backtest(
        "TEST",
        start=df["date"].iloc[280],
        threshold=0.3,
        history=df,
    )

    # Harness produced a decision per day in the window and computed metrics.
    assert result.n_decision_days > 100
    assert result.buy_hold_total_return > 0  # uptrend before noise
    assert result.pct_long + result.pct_short + result.pct_flat == pytest.approx(1.0)
    assert -1.0 <= result.strategy_max_dd <= 0.0
    assert -1.0 <= result.buy_hold_max_dd <= 0.0


def test_run_backtest_rejects_insufficient_history():
    prices = list(np.linspace(100, 110, 100))
    df = _synthetic_history(prices)

    with pytest.raises(ValueError):
        run_backtest("TEST", start=df["date"].iloc[10], threshold=0.5, history=df)


def test_run_backtest_reports_per_strategy_hit_rate():
    prices = list(np.linspace(100, 200, 600))
    df = _synthetic_history(prices)

    result = run_backtest(
        "TEST",
        start=df["date"].iloc[280],
        threshold=0.3,
        history=df,
    )

    expected_strategies = {
        "trend_50_200",
        "ts_momentum_12_1",
    }
    assert set(result.per_strategy_hit_rate.keys()) == expected_strategies
    for name, hit in result.per_strategy_hit_rate.items():
        assert 0.0 <= hit <= 1.0


def test_run_backtest_reports_multi_window_hit_rate():
    prices = list(np.linspace(100, 200, 600))
    df = _synthetic_history(prices)

    result = run_backtest(
        "TEST",
        start=df["date"].iloc[280],
        threshold=0.3,
        history=df,
    )

    # 1d, 5d, 21d, 252d hit rates all reported.
    assert set(result.per_strategy_hit_rate_by_window.keys()) == {1, 5, 21, 252}
    # Shorter windows have more samples than 252d in this 600-bar history.
    n_1d = result.per_strategy_n_by_window[1].get("trend_50_200", 0)
    n_252d = result.per_strategy_n_by_window[252].get("trend_50_200", 0)
    assert n_1d > n_252d


def test_run_backtest_horizon_selection():
    # Sanity: each horizon flag flows through to the result. Position-mix
    # divergence between 1W and 1Y was a meaningful test under v1's wide
    # weight differentials; with the post-2026-05-07 ensemble (trend +
    # 12-1 only, near-equal weights at every horizon), the three horizons
    # produce nearly-identical position mixes by design.
    prices = list(np.linspace(100, 200, 600))
    df = _synthetic_history(prices)

    one_y = run_backtest("TEST", start=df["date"].iloc[280], threshold=0.3, horizon="1Y", history=df)
    one_w = run_backtest("TEST", start=df["date"].iloc[280], threshold=0.3, horizon="1W", history=df)

    assert one_y.horizon == "1Y"
    assert one_w.horizon == "1W"
    assert one_y.n_decision_days == one_w.n_decision_days
    assert one_y.pct_long + one_y.pct_short + one_y.pct_flat == pytest.approx(1.0)
