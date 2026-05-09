"""Tests for `context_loaders.load_default_context`.

These exercise the offline path — fixture parquet files written into a
tmp directory, no yfinance calls.
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

from wisecat import context_loaders


@pytest.fixture(autouse=True)
def _reset_caches(monkeypatch, tmp_path):
    """Each test gets a fresh in-memory cache and an isolated parquet
    directory under tmp_path so cross-test state can't leak."""
    monkeypatch.setattr(context_loaders, "CONTEXT_CACHE_DIR", tmp_path)
    monkeypatch.setattr(context_loaders, "_EARNINGS_PATH", tmp_path / "earnings.parquet")
    context_loaders._reset_cache()
    yield
    context_loaders._reset_cache()


def _write_history(path: Path, n: int = 300) -> pd.DataFrame:
    """Write a small synthetic OHLCV parquet to `path`."""
    dates = pd.bdate_range("2024-01-01", periods=n).date
    closes = [100.0 + i * 0.1 for i in range(n)]
    df = pd.DataFrame({
        "date": dates,
        "open": closes,
        "high": [c * 1.01 for c in closes],
        "low": [c * 0.99 for c in closes],
        "close": closes,
        "volume": [1_000_000] * n,
    })
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(path, index=False)
    return df


def test_offline_with_no_cache_returns_empty_context(tmp_path):
    """No parquet on disk + allow_network=False → both fields are None."""
    ctx = context_loaders.load_default_context(allow_network=False)
    assert ctx.spy_history is None
    assert ctx.vix_history is None


def test_offline_with_cache_loads_both_symbols(tmp_path):
    """Pre-seeded parquet caches load correctly without network."""
    _write_history(tmp_path / "spy.parquet", n=400)
    _write_history(tmp_path / "vix.parquet", n=400)

    ctx = context_loaders.load_default_context(allow_network=False)
    assert ctx.spy_history is not None
    assert ctx.vix_history is not None
    assert "close" in ctx.spy_history.columns
    assert "date" in ctx.spy_history.columns
    assert len(ctx.spy_history) == 400


def test_partial_cache_loads_only_what_is_present(tmp_path):
    """SPY parquet present, VIX absent → spy populated, vix None."""
    _write_history(tmp_path / "spy.parquet", n=200)

    ctx = context_loaders.load_default_context(allow_network=False)
    assert ctx.spy_history is not None
    assert ctx.vix_history is None


def test_cached_history_normalizes_date_column(tmp_path):
    """Ensure `date` is `datetime.date`, not pandas Timestamp."""
    _write_history(tmp_path / "spy.parquet", n=50)
    ctx = context_loaders.load_default_context(allow_network=False)
    assert ctx.spy_history is not None
    import datetime as _dt
    assert isinstance(ctx.spy_history["date"].iloc[0], _dt.date)


def test_earnings_cache_loads_and_groups_per_ticker(tmp_path):
    """Pre-seeded earnings parquet groups dates per ticker."""
    import datetime as _dt
    rows = [
        {"ticker": "AAPL", "date": _dt.date(2024, 8, 1)},
        {"ticker": "AAPL", "date": _dt.date(2024, 11, 1)},
        {"ticker": "MSFT", "date": _dt.date(2024, 7, 30)},
    ]
    pd.DataFrame(rows).to_parquet(tmp_path / "earnings.parquet", index=False)

    ctx = context_loaders.load_default_context(allow_network=False)
    assert "AAPL" in ctx.earnings_dates
    assert "MSFT" in ctx.earnings_dates
    assert len(ctx.earnings_dates["AAPL"]) == 2
    assert ctx.earnings_dates["AAPL"][0] == _dt.date(2024, 8, 1)


def test_earnings_empty_when_no_cache_and_no_network(tmp_path):
    """No parquet + no network → empty earnings dict, not error."""
    ctx = context_loaders.load_default_context(allow_network=False)
    assert ctx.earnings_dates == {}
