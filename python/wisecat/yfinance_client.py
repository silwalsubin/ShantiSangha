"""yfinance fallback for long-range chart history.

Finnhub's free tier caps `/stock/candle` at ~1 year of daily data. For the
chart UI's 5Y / All ranges we use yfinance, which is free, key-less, and
returns unlimited daily history. Chart data only — technical strategies still
run off the Finnhub-cached `TickerDailyClose` table on the .NET side.
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
    # yfinance's column is "Date" (capital D) and is a Timestamp.
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
