"""yfinance for long-range chart history.

yfinance ≥ 0.2.55 auto-detects curl_cffi at import time and uses it for all
requests, which bypasses Yahoo's TLS-fingerprint block on AWS IP ranges. We
just need both packages installed; no explicit session juggling on our side.

Chart data only — technical strategies still run off the Finnhub-cached
`TickerDailyClose` table on the .NET side.
"""

import logging

import pandas as pd

logger = logging.getLogger(__name__)


class YFinanceUnavailable(RuntimeError):
    pass


def get_full_history(ticker: str) -> pd.DataFrame:
    """Returns the maximum available daily OHLCV. DataFrame is sorted ascending
    with a `date` column (datetime.date) plus `open`/`high`/`low`/`close`/`volume`.
    """
    try:
        import yfinance as yf
    except ImportError as e:
        raise YFinanceUnavailable(f"yfinance not installed: {e}") from e

    try:
        t = yf.Ticker(ticker)
        df = t.history(period="max", auto_adjust=True, raise_errors=False)
    except Exception as e:
        raise YFinanceUnavailable(f"yfinance error for {ticker}: {e}") from e

    if df.empty:
        raise YFinanceUnavailable(f"yfinance returned no rows for {ticker}")

    df = df.reset_index()
    df["date"] = pd.to_datetime(df["Date"]).dt.date
    df = df.rename(columns={
        "Open": "open",
        "High": "high",
        "Low": "low",
        "Close": "close",
        "Volume": "volume",
    })
    df = df[["date", "open", "high", "low", "close", "volume"]].sort_values("date").reset_index(drop=True)
    return df


def get_intraday_history(ticker: str) -> pd.DataFrame:
    """Returns 5-minute intraday bars for the most recent trading day. The
    DataFrame includes a `timestamp` column (timezone-aware datetime in
    UTC) — daily-only callers should not use this; it's chart-only.
    """
    try:
        import yfinance as yf
    except ImportError as e:
        raise YFinanceUnavailable(f"yfinance not installed: {e}") from e

    try:
        t = yf.Ticker(ticker)
        # Pull the last 5 trading days at 5-min resolution then filter to the
        # most recent date — handles weekends/holidays gracefully (returns the
        # last actual session instead of an empty result).
        df = t.history(period="5d", interval="5m", prepost=False, raise_errors=False)
    except Exception as e:
        raise YFinanceUnavailable(f"yfinance intraday error for {ticker}: {e}") from e

    if df.empty:
        raise YFinanceUnavailable(f"yfinance returned no intraday rows for {ticker}")

    df = df.reset_index()
    # Intraday index column is named "Datetime" in current yfinance.
    ts_col = "Datetime" if "Datetime" in df.columns else "Date"
    df["timestamp"] = pd.to_datetime(df[ts_col], utc=True)
    df = df.rename(columns={
        "Open": "open",
        "High": "high",
        "Low": "low",
        "Close": "close",
        "Volume": "volume",
    })

    # Filter to the most recent session present in the result.
    last_date = df["timestamp"].dt.date.max()
    df = df[df["timestamp"].dt.date == last_date]
    df = df[["timestamp", "open", "high", "low", "close", "volume"]].sort_values("timestamp").reset_index(drop=True)
    return df
