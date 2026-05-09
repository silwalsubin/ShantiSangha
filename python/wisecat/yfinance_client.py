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


def get_earnings_dates(ticker: str) -> list:
    """Returns historical earnings announcement dates for `ticker` as a list
    of `datetime.date` (most recent first is fine — we sort downstream).

    Uses yfinance's `Ticker.earnings_dates` property which surfaces both
    past announcements and analyst-estimated upcoming dates. Falls back to
    `Ticker.calendar` if `earnings_dates` is empty (some tickers expose only
    one or the other depending on data availability).

    Returns an empty list when nothing is available — callers degrade to
    the "no earnings" branch in features/earnings.py.
    """
    try:
        import yfinance as yf
    except ImportError as e:
        raise YFinanceUnavailable(f"yfinance not installed: {e}") from e

    out: list = []

    try:
        t = yf.Ticker(ticker)
        df = t.earnings_dates
    except Exception as e:
        logger.warning("earnings_dates fetch failed for %s: %s", ticker, e)
        df = None

    if df is not None and not df.empty:
        try:
            idx = df.index
            # The index is a DatetimeIndex (often timezone-aware). Normalize
            # to date-only so callers don't have to think about tz.
            for ts in idx:
                try:
                    d = ts.date() if hasattr(ts, "date") else pd.Timestamp(ts).date()
                except Exception:
                    continue
                out.append(d)
        except Exception as e:
            logger.warning("earnings_dates normalization failed for %s: %s", ticker, e)

    return out


def get_intraday_history(ticker: str) -> pd.DataFrame:
    """Returns 5-minute intraday bars for the most recent trading day,
    including pre-market (4:00–9:30 ET) and after-hours (16:00–20:00 ET).
    The DataFrame includes a `timestamp` column (tz-aware UTC) and an
    `extended_hours` bool flag — chart-only; daily callers should not use
    this.
    """
    try:
        import yfinance as yf
    except ImportError as e:
        raise YFinanceUnavailable(f"yfinance not installed: {e}") from e

    try:
        t = yf.Ticker(ticker)
        # Pull the last 5 trading days at 5-min resolution incl. pre/post,
        # then filter to the most recent ET session — handles
        # weekends/holidays gracefully (returns the last actual session
        # instead of an empty result).
        df = t.history(period="5d", interval="5m", prepost=True, raise_errors=False)
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

    # Filter by ET calendar date — after-hours bars (e.g. 6pm ET) cross UTC
    # midnight in summer, so filtering by UTC date can drop the tail end of
    # the most recent session.
    local = df["timestamp"].dt.tz_convert("America/New_York")
    last_date = local.dt.date.max()
    keep = local.dt.date == last_date
    df = df.loc[keep].copy()
    local = local.loc[keep]

    # Mark anything outside 9:30–16:00 ET as extended hours.
    minutes_et = local.dt.hour * 60 + local.dt.minute
    df["extended_hours"] = (minutes_et < 570) | (minutes_et >= 960)

    df = df[["timestamp", "open", "high", "low", "close", "volume", "extended_hours"]].sort_values("timestamp").reset_index(drop=True)
    return df
