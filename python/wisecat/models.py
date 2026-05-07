from datetime import date
from typing import Literal

from pydantic import BaseModel, Field


class BarInput(BaseModel):
    date: date
    open: float
    high: float
    low: float
    close: float
    volume: int


class ScoreItem(BaseModel):
    ticker: str
    bars: list[BarInput]
    price: float | None = None


class ScoreRequest(BaseModel):
    items: list[ScoreItem] = Field(min_length=1, max_length=500)
    as_of: date | None = Field(default=None, alias="asOf")


class StrategyContribution(BaseModel):
    name: str
    value: float
    contribution: float
    weight: float


class TickerScore(BaseModel):
    ticker: str
    price: float | None
    technical_score: float = Field(alias="technicalScore")
    signals: list[StrategyContribution]
    error: str | None = None

    model_config = {"populate_by_name": True}


class ScoreResponse(BaseModel):
    as_of: date = Field(alias="asOf")
    scores: list[TickerScore]

    model_config = {"populate_by_name": True}


class OhlcvBar(BaseModel):
    date: date
    open: float
    high: float
    low: float
    close: float
    volume: int


class HistoryResponse(BaseModel):
    ticker: str
    bars: list[OhlcvBar]


class Quote(BaseModel):
    ticker: str
    price: float
    bid: float | None = None
    ask: float | None = None
    last_size: int | None = Field(default=None, alias="lastSize")
    timestamp: str | None = None

    model_config = {"populate_by_name": True}


class HealthResponse(BaseModel):
    status: Literal["ok", "degraded", "down"]
    schwab_token_age_seconds: int | None = Field(default=None, alias="schwabTokenAgeSeconds")
    detail: str | None = None

    model_config = {"populate_by_name": True}
