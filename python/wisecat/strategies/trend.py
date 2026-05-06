import pandas as pd
from ta.trend import EMAIndicator


def score(df: pd.DataFrame) -> tuple[float, float]:
    """50/200 EMA cross. Returns (raw_value, score in [-1, 1]).

    raw_value is (ema50 - ema200) / ema200 — the percentage gap.
    Score saturates at ±5% gap.
    """
    if len(df) < 200:
        return 0.0, 0.0

    close = df["close"]
    ema50 = EMAIndicator(close, window=50).ema_indicator().iloc[-1]
    ema200 = EMAIndicator(close, window=200).ema_indicator().iloc[-1]

    if ema200 == 0 or pd.isna(ema50) or pd.isna(ema200):
        return 0.0, 0.0

    gap = (ema50 - ema200) / ema200
    score_value = max(-1.0, min(1.0, gap / 0.05))
    return float(gap), float(score_value)
