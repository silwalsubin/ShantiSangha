import pandas as pd


def score(df: pd.DataFrame) -> tuple[float, float]:
    """Volume confirmation of recent price move.

    Combines today's price change with how unusual today's volume is vs the
    prior 20 days. Strong volume on an up day → +; strong volume on a down
    day → -. Saturates at a ±4% effective move-times-volume signal.
    """
    if len(df) < 21:
        return 0.0, 0.0

    close = df["close"]
    vol = df["volume"]

    pct_change = (close.iloc[-1] - close.iloc[-2]) / close.iloc[-2] if close.iloc[-2] else 0.0
    vol_mean = vol.iloc[-21:-1].mean()
    if pd.isna(vol_mean) or vol_mean == 0:
        return 0.0, 0.0

    vol_std = vol.iloc[-21:-1].std()
    if pd.isna(vol_std) or vol_std == 0:
        # Constant prior volume — fall back to ratio vs mean.
        # 1.0 = same volume as mean; 2.0 = 2x mean; etc.
        vol_factor = vol.iloc[-1] / vol_mean - 1.0
    else:
        vol_factor = (vol.iloc[-1] - vol_mean) / vol_std

    raw = pct_change * max(-2.0, min(2.0, vol_factor))
    score_value = max(-1.0, min(1.0, raw / 0.04))
    return float(raw), float(score_value)
