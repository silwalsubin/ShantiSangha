from .trend import score as trend_score
from .ts_momentum import score as ts_momentum_score

# Active ensemble = trend + 12-1 momentum.
#
# The previous v1 stack also registered rsi_14, bollinger_pctb, volume_confirm,
# short_5d_return, and long_52w_distance. The 2026-05-07 basket tune
# (96-ticker NASDAQ-100 + 500-ticker S&P 500, 2014–2026, n≈1.48M samples
# per diagonal cell) showed all five at sub-coinflip hit rate at every
# horizon's native forward window. The two newest (short_5d_return,
# long_52w_distance) were deleted outright; the three legacy oscillators
# remain as files (`mean_reversion.py`, `momentum.py`, `volume.py`) but are
# not registered here — re-add them if a future signal redesign makes them
# earn weight on a real basket.
ALL_STRATEGIES = [
    ("trend_50_200", trend_score),
    ("ts_momentum_12_1", ts_momentum_score),
]

HORIZONS: tuple[str, ...] = ("1W", "1M", "1Y")

# Per-horizon weights. Each column must sum to 1.0.
#
# Weights derived from the 2026-05-07 basket evidence — at every horizon's
# native forward window, trend_50_200 and ts_momentum_12_1 are the only two
# strategies above 50% hit rate. They are the entire ensemble:
#
#                            NASDAQ-100         S&P 500
#   trend_50_200    ×252d:    59.7%             57.2%   (n=251K / 1.36M)
#   ts_momentum_12_1 ×252d:   60.3%             57.2%
#   trend_50_200    ×21d:     53.8%             52.7%
#   ts_momentum_12_1 ×21d:    53.9%             53.0%
#   trend_50_200    ×5d:      52.4%             51.8%
#   ts_momentum_12_1 ×5d:     52.6%             52.1%
#
# At every horizon, both signals lean ~equal-weight. The 1Y row gives trend
# slightly more (it captures the multi-year regime that 12-1's 252-day
# lookback can miss after a regime change); the 1W row gives ts_momentum
# slightly more (its monthly-skip window is more responsive to recent
# direction than a 50/200 cross at this horizon). 1M sits between them.
#
# All three columns are intentionally close — when only two signals work,
# the per-horizon distinction comes mostly from the astro side (panchang
# fast/slow split) and the per-horizon Buy/Sell threshold, not from
# wildly different technical weights. To re-derive: run
# `bash .claude/skills/wisecat-tune/scripts/run.sh`.
STRATEGY_WEIGHTS_BY_HORIZON: dict[str, dict[str, float]] = {
    "1W": {
        "trend_50_200":     0.45,
        "ts_momentum_12_1": 0.55,
    },
    "1M": {
        "trend_50_200":     0.50,
        "ts_momentum_12_1": 0.50,
    },
    "1Y": {
        "trend_50_200":     0.55,
        "ts_momentum_12_1": 0.45,
    },
}

# Legacy alias — the 1M weights ARE the canonical "default horizon". Anything
# in the codebase that reads STRATEGY_WEIGHTS gets the 1M view.
STRATEGY_WEIGHTS = STRATEGY_WEIGHTS_BY_HORIZON["1M"]
