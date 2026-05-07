"""yfinance for long-range chart history.

yfinance scrapes Yahoo Finance, which TLS-fingerprints requests and tends to
return empty/HTML pages (the famous "possibly delisted; no timezone found")
when called from AWS Lambda IP ranges with a stock urllib stack. We bypass
that by passing a `curl_cffi` session that impersonates real Chrome's TLS
fingerprint, which is how the rest of the open-source community works around
the same block.

Chart data only — technical strategies still run off the Finnhub-cached
`TickerDailyClose` table on the .NET side.
"""

import logging

import pandas as pd

logger = logging.getLogger(__name__)


class YFinanceUnavailable(RuntimeError):
    pass


_session = None


def _impersonating_session():
    """Lazy-built curl_cffi session with Chrome impersonation."""
    global _session
    if _session is not None:
        return _session
    try:
        from curl_cffi import requests as cffi_requests
    except ImportError as e:
        raise YFinanceUnavailable(f"curl_cffi not installed: {e}") from e
    _session = cffi_requests.Session(impersonate="chrome")
    return _session


def get_full_history(ticker: str) -> pd.DataFrame:
    """Returns the maximum available daily OHLCV. DataFrame is sorted ascending
    with a `date` column (datetime.date) plus `open`/`high`/`low`/`close`/`volume`.
    """
    try:
        import yfinance as yf
    except ImportError as e:
        raise YFinanceUnavailable(f"yfinance not installed: {e}") from e

    session = _impersonating_session()

    try:
        t = yf.Ticker(ticker, session=session)
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
