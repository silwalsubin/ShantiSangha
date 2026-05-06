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
)
from .scoring import score_ticker
from .settings import settings

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
            {"name": s.name, "value": s.value, "contribution": s.contribution}
            for s in score.signals
        ],
        "error": score.error,
    }
