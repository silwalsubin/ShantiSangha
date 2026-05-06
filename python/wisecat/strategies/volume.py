import pandas as pd


def score(df: pd.DataFrame) -> tuple[float, float]:
    """Volume confirmation of recent price move.

    Compares today's price change × today's volume z-score (vs 20d mean).
    Strong volume on an up day → +; strong volume on a down day → -.
    Saturates at ±2 std.
    """
    if len(df) < 21:
        return 0.0, 0.0

    close = df["close"]
    vol = df["volume"]

    pct_change = (close.iloc[-1] - close.iloc[-2]) / close.iloc[-2] if close.iloc[-2] else 0.0
    vol_mean = vol.iloc[-21:-1].mean()
    vol_std = vol.iloc[-21:-1].std()
    if pd.isna(vol_mean) or pd.isna(vol_std) or vol_std == 0:
        return 0.0, 0.0

    vol_z = (vol.iloc[-1] - vol_mean) / vol_std
    raw = pct_change * max(-2.0, min(2.0, vol_z))
    score_value = max(-1.0, min(1.0, raw / 0.04))
    return float(raw), float(score_value)
