import logging
from datetime import date

from fastapi import Depends, FastAPI, HTTPException, status

from .auth import require_internal_key
from .models import (
    HealthResponse,
    HistoryResponse,
    OhlcvBar,
    Quote,
    ScoreRequest,
    ScoreResponse,
)
from .finnhub_client import (
    FinnhubUnavailable,
    get_price_history,
    get_quotes,
    healthcheck,
)
from .scoring import score_ticker
from .settings import settings

logging.basicConfig(level=settings.log_level.upper())
logger = logging.getLogger("wisecat")

app = FastAPI(title="Wise Cat", version="0.1.0")


@app.get("/healthz", response_model=HealthResponse)
def healthz() -> HealthResponse:
    upstream_status, detail = healthcheck()
    return HealthResponse(status=upstream_status, detail=detail)


@app.post("/score", response_model=ScoreResponse, dependencies=[Depends(require_internal_key)])
def score(request: ScoreRequest) -> ScoreResponse:
    """Pure compute. Caller passes cached bars; we never hit Finnhub here."""
    import pandas as pd

    scores = []
    for item in request.items:
        if not item.bars:
            scores.append(score_ticker(item.ticker, df=pd.DataFrame(), price=item.price))
            continue
        df = pd.DataFrame(
            [
                {"date": b.date, "open": b.open, "high": b.high, "low": b.low, "close": b.close, "volume": b.volume}
                for b in item.bars
            ]
        ).sort_values("date").reset_index(drop=True)
        scores.append(score_ticker(item.ticker, df, item.price))

    return ScoreResponse(asOf=request.as_of or date.today(), scores=scores)


@app.get("/quote/{ticker}", response_model=Quote, dependencies=[Depends(require_internal_key)])
def quote(ticker: str) -> Quote:
    try:
        quotes = get_quotes([ticker])
    except FinnhubUnavailable as e:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(e))

    payload = quotes.get(ticker)
    if not payload or payload.get("price") is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, f"no quote for {ticker}")

    return Quote(
        ticker=ticker,
        price=payload["price"],
        bid=payload.get("bid"),
        ask=payload.get("ask"),
        lastSize=payload.get("last_size"),
        timestamp=str(payload.get("timestamp")) if payload.get("timestamp") is not None else None,
    )


@app.get(
    "/history/{ticker}",
    response_model=HistoryResponse,
    dependencies=[Depends(require_internal_key)],
)
def history(
    ticker: str,
    days: int | None = None,
    from_date: date | None = None,
    to_date: date | None = None,
) -> HistoryResponse:
    """Delta-friendly history. .NET passes `from_date` to fetch only missing bars.

    - If `from_date` is set, return bars >= from_date (and <= to_date if set).
    - Else use `days` lookback (default settings.history_lookback_days).
    """
    try:
        if from_date is not None:
            today = date.today()
            lookback = (today - from_date).days + 1
            df = get_price_history(ticker, lookback_days=lookback)
            df = df[df["date"] >= from_date]
            if to_date is not None:
                df = df[df["date"] <= to_date]
        else:
            df = get_price_history(ticker, lookback_days=days)
    except FinnhubUnavailable as e:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(e))

    bars = [
        OhlcvBar(
            date=row.date,
            open=float(row.open),
            high=float(row.high),
            low=float(row.low),
            close=float(row.close),
            volume=int(row.volume),
        )
        for row in df.itertuples()
    ]
    return HistoryResponse(ticker=ticker, bars=bars)
