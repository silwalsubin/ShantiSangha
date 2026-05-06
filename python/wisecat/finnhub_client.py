"""Thin Finnhub client. Free tier covers US-stock quotes + daily candles.

Quotes are 15-min delayed on the free tier; sub-second SIP requires a paid plan
(swap WISECAT_FINNHUB_API_KEY, no code change). Limits: 60 calls/min on free.
"""

import logging
import os
import time
from typing import Any

import httpx
import pandas as pd

from .settings import settings

logger = logging.getLogger(__name__)


class FinnhubUnavailable(RuntimeError):
    pass


_client: httpx.Client | None = None
_cached_api_key: str | None = None


def _http() -> httpx.Client:
    global _client
    if _client is None:
        _client = httpx.Client(base_url=settings.finnhub_base_url, timeout=10.0)
    return _client


def _api_key() -> str:
    """Resolve the Finnhub key — env var first (local dev), then Secrets Manager (Lambda)."""
    if settings.finnhub_api_key:
        return settings.finnhub_api_key

    global _cached_api_key
    if _cached_api_key:
        return _cached_api_key

    secret_id = os.environ.get("WISECAT_FINNHUB_SECRET_ID", "shantisangha/finnhub_api_key")
    try:
        import boto3
        sm = boto3.client("secretsmanager")
        resp = sm.get_secret_value(SecretId=secret_id)
        _cached_api_key = resp["SecretString"]
        return _cached_api_key
    except Exception as e:
        raise FinnhubUnavailable(f"unable to resolve Finnhub API key: {e}") from e


def _get(path: str, params: dict[str, Any]) -> dict:
    try:
        key = _api_key()
    except FinnhubUnavailable:
        raise

    params = {**params, "token": key}
    try:
        resp = _http().get(path, params=params)
    except httpx.HTTPError as e:
        raise FinnhubUnavailable(f"finnhub network error: {e}") from e

    if resp.status_code == 429:
        raise FinnhubUnavailable("finnhub rate limit (60/min on free tier)")
    if resp.status_code >= 400:
        raise FinnhubUnavailable(f"finnhub {path} returned {resp.status_code}: {resp.text[:200]}")
    return resp.json()


def get_quotes(tickers: list[str]) -> dict[str, dict]:
    """Per-ticker fan-out (Finnhub /quote takes one symbol per call).

    Returns {ticker: {price, prev_close, day_high, day_low, timestamp}}.
    Missing tickers are absent.
    """
    out: dict[str, dict] = {}
    for ticker in tickers:
        try:
            data = _get("/quote", {"symbol": ticker})
        except FinnhubUnavailable:
            raise
        except Exception:
            logger.exception("quote fetch failed for %s", ticker)
            continue

        if not data or data.get("c") in (None, 0):
            continue

        out[ticker] = {
            "price": float(data["c"]),
            "bid": None,
            "ask": None,
            "last_size": None,
            "prev_close": float(data.get("pc", 0)) or None,
            "day_high": float(data.get("h", 0)) or None,
            "day_low": float(data.get("l", 0)) or None,
            "timestamp": data.get("t"),
        }
    return out


def get_price_history(ticker: str, lookback_days: int | None = None) -> pd.DataFrame:
    """Daily OHLCV via Finnhub /stock/candle."""
    days = lookback_days or settings.history_lookback_days
    now = int(time.time())
    start = now - (days + 7) * 86_400  # extra week buffer for non-trading days

    data = _get(
        "/stock/candle",
        {"symbol": ticker, "resolution": "D", "from": start, "to": now},
    )

    if data.get("s") != "ok":
        return pd.DataFrame(columns=["date", "open", "high", "low", "close", "volume"])

    df = pd.DataFrame({
        "date": pd.to_datetime(data["t"], unit="s", utc=True).date,
        "open": data["o"],
        "high": data["h"],
        "low": data["l"],
        "close": data["c"],
        "volume": data["v"],
    })
    df = df.sort_values("date").reset_index(drop=True)
    if days < len(df):
        df = df.tail(days).reset_index(drop=True)
    return df


def healthcheck() -> tuple[str, str | None]:
    try:
        _api_key()
    except FinnhubUnavailable as e:
        return "degraded", str(e)
    try:
        # cheap probe — quote SPY
        _get("/quote", {"symbol": "SPY"})
        return "ok", None
    except FinnhubUnavailable as e:
        return "degraded", str(e)
    except Exception as e:
        logger.exception("unexpected health-check error")
        return "down", f"{type(e).__name__}: {e}"
