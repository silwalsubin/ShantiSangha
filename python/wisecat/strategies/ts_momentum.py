import math

import pandas as pd


def score(df: pd.DataFrame) -> tuple[float, float]:
    """12-1 time-series momentum (Moskowitz/Asness 2012).

    The 12-month return *excluding the most recent month* — i.e. the
    252-day return ending 21 trading days ago. Skipping the most recent
    month removes the 1-month reversal effect that contaminates a naive
    12-month lookback.

    Returns (raw_return, score in [-1, 1]). Score is `tanh(return / 0.20)`,
    so a +20% trailing year scores ≈+0.76, +40% ≈+0.96, saturating beyond.
    """
    if len(df) < 274:
        return 0.0, 0.0

    close = df["close"]
    end_price = close.iloc[-22]   # 21 trading days ago (skip most recent month)
    start_price = close.iloc[-274]  # 252 trading days before that
    if start_price == 0 or pd.isna(start_price) or pd.isna(end_price):
        return 0.0, 0.0

    raw = float(end_price / start_price - 1.0)
    score_value = math.tanh(raw / 0.20)
    return raw, max(-1.0, min(1.0, float(score_value)))
