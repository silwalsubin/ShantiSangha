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


class HorizonScore(BaseModel):
    """Per-horizon technical roll-up. One per horizon (1W, 1M, 1Y).

    `score` is the legacy [-1, +1] composite from the weighted-sum path;
    kept for backwards compatibility with the .NET `HorizonTechnicalScore`
    deserializer that still reads it. The `p_*` triple + `expected_return`
    are populated by the GBM scoring path. On the legacy path they default
    to the neutral verdict `(p_hold = 1.0, others = 0.0)`.
    """
    score: float
    p_buy: float = Field(default=0.0, alias="pBuy")
    p_hold: float = Field(default=1.0, alias="pHold")
    p_sell: float = Field(default=0.0, alias="pSell")
    expected_return: float = Field(default=0.0, alias="expectedReturn")
    signals: list[StrategyContribution]

    model_config = {"populate_by_name": True}


class TickerScore(BaseModel):
    ticker: str
    price: float | None
    # Per-horizon scores keyed by "1W" | "1M" | "1Y".
    horizons: dict[str, HorizonScore]
    error: str | None = None

    @property
    def technical_score(self) -> float:
        """Legacy single-horizon view = the 1M score. Kept for callers that
        haven't migrated to the per-horizon API."""
        return self.horizons["1M"].score if "1M" in self.horizons else 0.0

    @property
    def signals(self) -> list[StrategyContribution]:
        """Legacy single-horizon view = the 1M signal contributions."""
        return self.horizons["1M"].signals if "1M" in self.horizons else []

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
