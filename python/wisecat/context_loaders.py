"""Populate `FeatureContext` with the cross-sectional and regime data
that several Phase 3 features need.

Today this is just SPY (cross-sectional baseline) and `^VIX` (regime
gate). Earnings dates, sector map, and multi-asset macro come later.

Storage strategy:
- yfinance fetches happen at training time (`--allow-network`) and write
  parquet files into `python/wisecat/data/context/`.
- Those parquet files are committed to the repo and bundled into the
  Lambda container image at build time. Lambda reads from disk only —
  no network calls during scoring.
- Module-level cache avoids re-reading the parquet on every score call
  within a warm process.
"""

from __future__ import annotations

import logging
from pathlib import Path
from threading import Lock

import pandas as pd

from .features import FeatureContext

logger = logging.getLogger(__name__)


PACKAGE_DIR = Path(__file__).resolve().parent
CONTEXT_CACHE_DIR = PACKAGE_DIR / "data" / "context"

# Symbols we pull and the parquet filename we cache them under. Caret
# tickers (^VIX) need filename sanitization since some filesystems and
# tools dislike the caret.
_SYMBOL_FILES: dict[str, str] = {
    "SPY": "spy.parquet",
    "^VIX": "vix.parquet",
}

# Process-wide cache. Lambda warm invocations reuse it; tests reset it
# explicitly via `_reset_cache()`.
_HISTORY_CACHE: dict[str, pd.DataFrame] = {}
_CACHE_LOCK = Lock()


def _cache_path(symbol: str) -> Path:
    fname = _SYMBOL_FILES.get(symbol)
    if fname is None:
        # Fallback: strip non-alphanumerics for unknown symbols.
        fname = "".join(ch for ch in symbol.lower() if ch.isalnum() or ch == "_") + ".parquet"
    return CONTEXT_CACHE_DIR / fname


def _load_one(symbol: str, allow_network: bool) -> pd.DataFrame | None:
    """Return the cached history for `symbol`, fetching from yfinance only
    if `allow_network=True` and the parquet cache is missing.

    Returns None if neither path produces data — callers degrade gracefully.
    """
    with _CACHE_LOCK:
        if symbol in _HISTORY_CACHE:
            return _HISTORY_CACHE[symbol]

        path = _cache_path(symbol)
        if path.exists():
            try:
                df = pd.read_parquet(path)
                df = _normalize(df)
                _HISTORY_CACHE[symbol] = df
                return df
            except Exception as e:
                logger.warning("context cache read failed for %s (%s); refetching", symbol, e)

        if not allow_network:
            logger.info("no cached context for %s and network fetch disabled", symbol)
            return None

        try:
            from .yfinance_client import get_full_history, YFinanceUnavailable
            df = get_full_history(symbol)
        except Exception as e:
            logger.warning("yfinance fetch for %s failed: %s", symbol, e)
            return None

        df = _normalize(df)
        try:
            CONTEXT_CACHE_DIR.mkdir(parents=True, exist_ok=True)
            df.to_parquet(path, index=False)
        except Exception as e:
            logger.warning("context cache write failed for %s (%s)", symbol, e)
        _HISTORY_CACHE[symbol] = df
        return df


def _normalize(df: pd.DataFrame) -> pd.DataFrame:
    """Coerce `date` to `datetime.date`, drop dupes, sort ascending. Other
    feature modules already handle missing OHLCV columns defensively."""
    df = df.copy()
    if "date" not in df.columns:
        raise ValueError("context history DataFrame missing 'date' column")
    df["date"] = pd.to_datetime(df["date"]).dt.date
    df = df.drop_duplicates(subset="date").sort_values("date").reset_index(drop=True)
    if "close" in df.columns:
        df["close"] = pd.to_numeric(df["close"], errors="coerce")
    return df


def load_default_context(allow_network: bool = False) -> FeatureContext:
    """Load SPY + VIX into a FeatureContext.

    Set `allow_network=True` only at training time (or when explicitly
    bootstrapping the parquet cache). Lambda inference always passes
    `False` — it reads from the parquet bundled into the container.
    """
    spy = _load_one("SPY", allow_network=allow_network)
    vix = _load_one("^VIX", allow_network=allow_network)
    return FeatureContext(spy_history=spy, vix_history=vix)


def _reset_cache() -> None:
    """Test hook — clears the in-memory cache so a fresh fixture takes effect."""
    with _CACHE_LOCK:
        _HISTORY_CACHE.clear()
