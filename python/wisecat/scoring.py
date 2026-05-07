"""Compose per-ticker technical scores from individual strategies.

For each ticker we compute every strategy's `(raw, value)` exactly once,
then fan that out to the three horizons (1W / 1M / 1Y) using each
horizon's weight vector. This keeps the cost of multi-horizon scoring
flat — the strategies (which own the heavy pandas / TA work) run once,
and the per-horizon weighting is just multiplications.
"""

import logging

import pandas as pd

from .models import HorizonScore, StrategyContribution, TickerScore
from .strategies import ALL_STRATEGIES, HORIZONS, STRATEGY_WEIGHTS_BY_HORIZON

logger = logging.getLogger(__name__)


def score_ticker(ticker: str, df: pd.DataFrame, price: float | None) -> TickerScore:
    if df.empty:
        return TickerScore(
            ticker=ticker,
            price=price,
            horizons={h: HorizonScore(score=0.0, signals=[]) for h in HORIZONS},
            error="no historical data",
        )

    # Compute each strategy's (raw, value) once.
    strategy_results: dict[str, tuple[float, float]] = {}
    for name, strategy_fn in ALL_STRATEGIES:
        try:
            raw, value = strategy_fn(df)
        except Exception as e:
            logger.warning("strategy %s failed for %s: %s", name, ticker, e)
            continue
        strategy_results[name] = (raw, value)

    # Fan out to per-horizon roll-ups.
    horizons: dict[str, HorizonScore] = {}
    for horizon in HORIZONS:
        weights = STRATEGY_WEIGHTS_BY_HORIZON[horizon]
        contributions: list[StrategyContribution] = []
        total = 0.0
        for name, (raw, value) in strategy_results.items():
            weight = weights.get(name, 0.0)
            contributions.append(
                StrategyContribution(
                    name=name,
                    value=raw,
                    contribution=value * weight,
                    weight=weight,
                )
            )
            total += value * weight
        horizons[horizon] = HorizonScore(score=total, signals=contributions)

    return TickerScore(ticker=ticker, price=price, horizons=horizons)
