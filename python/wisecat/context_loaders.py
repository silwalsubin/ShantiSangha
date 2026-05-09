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


def load_default_context(
    allow_network: bool = False,
    tickers_for_earnings: list[str] | None = None,
) -> FeatureContext:
    """Load SPY + VIX + earnings dates into a FeatureContext.

    Set `allow_network=True` only at training time (or when explicitly
    bootstrapping the parquet cache). Lambda inference always passes
    `False` — it reads from the parquet bundled into the container.

    `tickers_for_earnings` is the basket to bootstrap when the earnings
    parquet is missing AND `allow_network=True`. At inference time pass
    `None`; the bundled parquet covers whatever was bootstrapped at
    training time.
    """
    spy = _load_one("SPY", allow_network=allow_network)
    vix = _load_one("^VIX", allow_network=allow_network)
    earnings = _load_earnings(
        tickers=tickers_for_earnings, allow_network=allow_network
    )
    return FeatureContext(
        spy_history=spy,
        vix_history=vix,
        earnings_dates=earnings,
    )


# ---------------------------------------------------------------------------
# Earnings-dates loader
# ---------------------------------------------------------------------------


_EARNINGS_PATH = CONTEXT_CACHE_DIR / "earnings.parquet"
_EARNINGS_CACHE: dict[str, list] | None = None


def _load_earnings(
    tickers: list[str] | None, allow_network: bool
) -> dict[str, list]:
    """Return {ticker: [datetime.date, ...]} for every ticker we have
    earnings dates for.

    Reads the bundled `data/context/earnings.parquet` if it exists.
    Bootstraps from yfinance only when the parquet is missing and
    `allow_network=True`. The bootstrap pulls every ticker in `tickers`
    once and writes a single parquet (columns: ticker, date).
    """
    global _EARNINGS_CACHE

    with _CACHE_LOCK:
        if _EARNINGS_CACHE is not None:
            return _EARNINGS_CACHE

        if _EARNINGS_PATH.exists():
            try:
                df = pd.read_parquet(_EARNINGS_PATH)
                _EARNINGS_CACHE = _earnings_df_to_dict(df)
                return _EARNINGS_CACHE
            except Exception as e:
                logger.warning(
                    "earnings cache read failed (%s); will refetch if allowed", e
                )

        if not allow_network or not tickers:
            _EARNINGS_CACHE = {}
            return _EARNINGS_CACHE

        try:
            from .yfinance_client import get_earnings_dates
        except Exception as e:
            logger.warning("yfinance unavailable for earnings bootstrap: %s", e)
            _EARNINGS_CACHE = {}
            return _EARNINGS_CACHE

        rows: list[dict] = []
        result: dict[str, list] = {}
        for ticker in tickers:
            ticker = ticker.upper()
            try:
                dates = get_earnings_dates(ticker)
            except Exception as e:
                logger.warning("earnings fetch failed for %s: %s", ticker, e)
                continue
            if not dates:
                continue
            uniq = sorted(set(dates))
            result[ticker] = uniq
            for d in uniq:
                rows.append({"ticker": ticker, "date": d})

        if rows:
            try:
                CONTEXT_CACHE_DIR.mkdir(parents=True, exist_ok=True)
                pd.DataFrame(rows).to_parquet(_EARNINGS_PATH, index=False)
            except Exception as e:
                logger.warning("earnings cache write failed: %s", e)

        _EARNINGS_CACHE = result
        return _EARNINGS_CACHE


def _earnings_df_to_dict(df: pd.DataFrame) -> dict[str, list]:
    if df.empty or "ticker" not in df.columns or "date" not in df.columns:
        return {}
    df = df.copy()
    df["date"] = pd.to_datetime(df["date"]).dt.date
    out: dict[str, list] = {}
    for ticker, sub in df.groupby("ticker"):
        out[str(ticker).upper()] = sorted(set(sub["date"].tolist()))
    return out


def _reset_cache() -> None:
    """Test hook — clears the in-memory cache so a fresh fixture takes effect."""
    global _EARNINGS_CACHE
    with _CACHE_LOCK:
        _HISTORY_CACHE.clear()
        _EARNINGS_CACHE = None
