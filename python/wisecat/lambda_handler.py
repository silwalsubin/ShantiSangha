"""AWS Lambda entry point — action-based dispatcher.

The .NET caller invokes this Lambda directly via the AWS SDK with payloads like:

    {"action": "score", "items": [...]}
    {"action": "history", "ticker": "AAPL", "fromDate": "2026-04-01"}
    {"action": "quote", "ticker": "AAPL"}
    {"action": "healthz"}

Returns plain JSON. On failure, raises — the Lambda runtime surfaces the error
back to the caller as `FunctionError`. IAM (lambda:InvokeFunction on the .NET
task role) is the auth boundary; there's no shared bearer-token check here.
"""

import logging
from datetime import date
from typing import Any

from .finnhub_client import (
    FinnhubUnavailable,
    get_price_history,
    get_quotes,
    healthcheck,
    search_symbols,
)
from .scoring import score_ticker
from .settings import settings
from .yfinance_client import YFinanceUnavailable, get_full_history, get_intraday_history

logging.basicConfig(level=settings.log_level.upper())
logger = logging.getLogger("wisecat.lambda")


def handler(event: dict, context: Any) -> dict:
    action = (event or {}).get("action")
    if not action:
        raise ValueError("missing 'action' in event payload")

    if action == "healthz":
        return _healthz()
    if action == "score":
        return _score(event)
    if action == "history":
        return _history(event)
    if action == "quote":
        return _quote(event)
    if action == "symbolSearch":
        return _symbol_search(event)
    if action == "chartHistory":
        return _chart_history(event)

    raise ValueError(f"unknown action: {action}")


def _healthz() -> dict:
    status, detail = healthcheck()
    return {"status": status, "detail": detail}


def _score(event: dict) -> dict:
    import pandas as pd

    items = event.get("items") or []
    if not isinstance(items, list) or not items:
        raise ValueError("'items' must be a non-empty list")

    as_of = event.get("asOf") or date.today().isoformat()
    scores = []
    for item in items:
        ticker = item.get("ticker")
        bars = item.get("bars") or []
        price = item.get("price")
        if not ticker:
            continue
        if not bars:
            scores.append(_serialize_score(score_ticker(ticker, df=pd.DataFrame(), price=price)))
            continue
        df = pd.DataFrame(bars).sort_values("date").reset_index(drop=True)
        scores.append(_serialize_score(score_ticker(ticker, df, price)))

    return {"asOf": as_of, "scores": scores}


def _history(event: dict) -> dict:
    ticker = event.get("ticker")
    if not ticker:
        raise ValueError("'ticker' required")

    from_date_str = event.get("fromDate")
    days = event.get("days")

    try:
        if from_date_str:
            from_date = date.fromisoformat(from_date_str)
            today = date.today()
            lookback = (today - from_date).days + 1
            df = get_price_history(ticker, lookback_days=lookback)
            df = df[df["date"] >= from_date]
        else:
            df = get_price_history(ticker, lookback_days=days)
    except FinnhubUnavailable as e:
        raise RuntimeError(f"finnhub unavailable: {e}") from e

    bars = [
        {
            "date": row.date.isoformat(),
            "open": float(row.open),
            "high": float(row.high),
            "low": float(row.low),
            "close": float(row.close),
            "volume": int(row.volume),
        }
        for row in df.itertuples()
    ]
    return {"ticker": ticker, "bars": bars}


_PERIOD_DAYS = {
    "1w": 7,
    "1mo": 31,
    "3mo": 92,
    "1y": 365,
    "5y": 1826,
    # "ytd" handled by year-start filter
    # "max" handled separately
}


def _chart_history(event: dict) -> dict:
    """Returns chart-display bars for the requested period plus an `aggregates`
    block computed off the FULL available history (so 52w / all-time stats are
    independent of the selected period)."""
    from datetime import date as _date, timedelta

    ticker = event.get("ticker")
    if not ticker:
        raise ValueError("'ticker' required")
    period = (event.get("period") or "1y").lower()
    if period not in _PERIOD_DAYS and period not in ("max", "ytd", "1d"):
        raise ValueError(f"unknown period: {period}")

    try:
        df = get_full_history(ticker)
    except YFinanceUnavailable as e:
        raise RuntimeError(f"yfinance unavailable: {e}") from e

    if df.empty:
        return {"ticker": ticker, "period": period, "bars": [], "aggregates": None}

    # Aggregates from full history.
    today = _date.today()
    last52 = df[df["date"] >= (today - timedelta(days=365))]
    aggregates = {
        "currentPrice": float(df["close"].iloc[-1]),
        "previousClose": float(df["close"].iloc[-2]) if len(df) >= 2 else None,
        "weekHigh52": float(last52["close"].max()) if not last52.empty else None,
        "weekLow52": float(last52["close"].min()) if not last52.empty else None,
        "allTimeHigh": float(df["close"].max()),
        "allTimeLow": float(df["close"].min()),
        "firstDate": df["date"].iloc[0].isoformat(),
        "latestDate": df["date"].iloc[-1].isoformat(),
    }

    # 1D path: pull intraday bars (5-min) instead of filtering daily history.
    # Aggregates still come from the daily history above (52w/all-time are not
    # intraday concepts).
    if period == "1d":
        try:
            intraday = get_intraday_history(ticker)
        except YFinanceUnavailable as e:
            raise RuntimeError(f"yfinance intraday unavailable: {e}") from e

        bars = [
            {
                "date": row.timestamp.isoformat(),  # full ISO incl. timezone
                "open": float(row.open),
                "high": float(row.high),
                "low": float(row.low),
                "close": float(row.close),
                "volume": int(row.volume) if row.volume == row.volume else 0,
            }
            for row in intraday.itertuples()
        ]
        return {"ticker": ticker, "period": period, "bars": bars, "aggregates": aggregates}

    # Daily-resolution paths.
    from datetime import date as _date_cls
    if period == "max":
        bars_df = df
    elif period == "ytd":
        cutoff = _date_cls(today.year, 1, 1)
        bars_df = df[df["date"] >= cutoff]
    else:
        cutoff = today - timedelta(days=_PERIOD_DAYS[period])
        bars_df = df[df["date"] >= cutoff]

    bars = [
        {
            "date": row.date.isoformat(),
            "open": float(row.open),
            "high": float(row.high),
            "low": float(row.low),
            "close": float(row.close),
            "volume": int(row.volume) if row.volume == row.volume else 0,  # NaN guard
        }
        for row in bars_df.itertuples()
    ]
    return {"ticker": ticker, "period": period, "bars": bars, "aggregates": aggregates}


def _symbol_search(event: dict) -> dict:
    query = (event.get("query") or "").strip()
    limit = int(event.get("limit") or 10)
    if not query:
        return {"results": []}

    try:
        results = search_symbols(query, limit=limit)
    except FinnhubUnavailable as e:
        raise RuntimeError(f"finnhub unavailable: {e}") from e

    return {"results": results}


def _quote(event: dict) -> dict:
    ticker = event.get("ticker")
    if not ticker:
        raise ValueError("'ticker' required")

    try:
        quotes = get_quotes([ticker])
    except FinnhubUnavailable as e:
        raise RuntimeError(f"finnhub unavailable: {e}") from e

    payload = quotes.get(ticker)
    if not payload or payload.get("price") is None:
        return {"ticker": ticker, "price": None}

    return {
        "ticker": ticker,
        "price": payload["price"],
        "bid": payload.get("bid"),
        "ask": payload.get("ask"),
        "lastSize": payload.get("last_size"),
        "timestamp": str(payload.get("timestamp")) if payload.get("timestamp") is not None else None,
    }


def _serialize_score(score) -> dict:
    return {
        "ticker": score.ticker,
        "price": score.price,
        "technicalScore": score.technical_score,
        "signals": [
            {
                "name": s.name,
                "value": s.value,
                "contribution": s.contribution,
                "weight": s.weight,
            }
            for s in score.signals
        ],
        "error": score.error,
    }
