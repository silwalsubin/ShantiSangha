import pandas as pd
from ta.trend import EMAIndicator


def score(df: pd.DataFrame) -> tuple[float, float]:
    """5/20 EMA cross — fast trend confirmation.

    Designed to update visibly day to day so the 1W verdict can flip on
    a real change in short-term direction. Whipsaws on chop, so weighted
    small at 1M and zero at 1Y where the slow trend / 12-1 momentum
    signals dominate.

    raw_value is (ema5 - ema20) / ema20 — percentage gap. Score saturates
    at ±2% gap (tighter than the 50/200 cross because 5/20 separation is
    naturally smaller).
    """
    if len(df) < 20:
        return 0.0, 0.0

    close = df["close"]
    ema5 = EMAIndicator(close, window=5).ema_indicator().iloc[-1]
    ema20 = EMAIndicator(close, window=20).ema_indicator().iloc[-1]

    if ema20 == 0 or pd.isna(ema5) or pd.isna(ema20):
        return 0.0, 0.0

    gap = (ema5 - ema20) / ema20
    score_value = max(-1.0, min(1.0, gap / 0.02))
    return float(gap), float(score_value)
