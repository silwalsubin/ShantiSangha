import pandas as pd
from ta.volatility import BollingerBands


def score(df: pd.DataFrame) -> tuple[float, float]:
    """Bollinger %B (20-period, 2 std). Returns (pct_b, score in [-1, 1]).

    %B = (close - lower) / (upper - lower). Below 0 → strong oversold (+1),
    above 1 → strong overbought (-1). Linear in between, neutral at 0.5.
    """
    if len(df) < 20:
        return 0.0, 0.0

    bb = BollingerBands(df["close"], window=20, window_dev=2)
    upper = bb.bollinger_hband().iloc[-1]
    lower = bb.bollinger_lband().iloc[-1]
    close = df["close"].iloc[-1]

    if pd.isna(upper) or pd.isna(lower) or upper == lower:
        return 0.0, 0.0

    pct_b = (close - lower) / (upper - lower)
    score_value = max(-1.0, min(1.0, (0.5 - pct_b) * 2))
    return float(pct_b), float(score_value)
