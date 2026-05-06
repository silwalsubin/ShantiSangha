"""Compose per-ticker technical scores from individual strategies."""

import logging

import pandas as pd

from .models import StrategyContribution, TickerScore
from .strategies import ALL_STRATEGIES

logger = logging.getLogger(__name__)


def score_ticker(ticker: str, df: pd.DataFrame, price: float | None) -> TickerScore:
    if df.empty:
        return TickerScore(
            ticker=ticker,
            price=price,
            technicalScore=0.0,
            signals=[],
            error="no historical data",
        )

    contributions: list[StrategyContribution] = []
    total = 0.0
    weight_per = 1.0 / len(ALL_STRATEGIES)

    for name, strategy_fn in ALL_STRATEGIES:
        try:
            raw, value = strategy_fn(df)
        except Exception as e:
            logger.warning("strategy %s failed for %s: %s", name, ticker, e)
            continue
        contributions.append(
            StrategyContribution(name=name, value=raw, contribution=value * weight_per)
        )
        total += value * weight_per

    return TickerScore(
        ticker=ticker,
        price=price,
        technicalScore=total,
        signals=contributions,
    )
