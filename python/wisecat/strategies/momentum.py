import pandas as pd
from ta.momentum import RSIIndicator


def score(df: pd.DataFrame) -> tuple[float, float]:
    """RSI(14). Returns (rsi_value, score in [-1, 1]).

    Oversold (RSI < 30) is bullish (+); overbought (RSI > 70) is bearish (-).
    Score is linear between 30 and 70, saturates beyond.
    """
    if len(df) < 15:
        return 0.0, 0.0

    rsi = RSIIndicator(df["close"], window=14).rsi().iloc[-1]
    if pd.isna(rsi):
        return 0.0, 0.0

    if rsi <= 30:
        score_value = 1.0
    elif rsi >= 70:
        score_value = -1.0
    else:
        score_value = (50 - rsi) / 20.0

    return float(rsi), float(max(-1.0, min(1.0, score_value)))
