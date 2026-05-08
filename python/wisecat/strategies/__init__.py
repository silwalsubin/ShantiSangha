from .fast_trend import score as fast_trend_score
from .trend import score as trend_score
from .ts_momentum import score as ts_momentum_score

# Active ensemble = 50/200 trend + 12-1 momentum + 5/20 fast trend.
#
# trend_50_200 and ts_momentum_12_1 are the diagonal-cell winners from the
# 2026-05-07 basket tune (NASDAQ-100 + S&P 500, 2014–2026): both above 50%
# hit rate at every horizon's native forward window, while every other v1
# strategy was sub-coinflip.
#
# fast_trend_5_20 was added on 2026-05-08 to give the 1W verdict something
# that updates visibly on daily closes — a single +3% day moves a 5/20
# EMA gap noticeably, while 50/200 EMA and 12-1 momentum barely budge.
# It is intentionally weighted small at 1M and zero at 1Y so it cannot
# whipsaw the longer-horizon verdicts; rerun the basket tune before
# trusting it past the short horizon.
#
# The legacy oscillators (mean_reversion.py, momentum.py, volume.py) remain
# as files but are not registered — re-add them if a future signal redesign
# makes them earn weight on a real basket.
ALL_STRATEGIES = [
    ("trend_50_200", trend_score),
    ("ts_momentum_12_1", ts_momentum_score),
    ("fast_trend_5_20", fast_trend_score),
]

HORIZONS: tuple[str, ...] = ("1W", "1M", "1Y")

# Per-horizon weights. Each column must sum to 1.0.
#
# 1W: fast_trend_5_20 takes 25% — enough to flip a borderline Buy/Hold/Sell
#     when short-term direction breaks one way, not enough to override a
#     genuine 12-1 / 50-200 alignment.
# 1M: fast_trend_5_20 trimmed to 10% — a nudge, not a driver.
# 1Y: fast_trend_5_20 stays at 0% — too noisy for the multi-year regime.
#
# trend_50_200 still earns its largest weight at 1Y (captures the slow
# regime); ts_momentum_12_1 still earns its largest at 1W (its monthly-skip
# window is more responsive than a 50/200 cross at this horizon).
#
# All three columns intentionally lean similar — when only a couple of
# signals work in basket-evidence terms, the per-horizon distinction comes
# more from the Buy/Sell threshold than from wildly different weights. To
# re-derive after adding fast_trend_5_20 to the universe of candidate
# strategies, run `bash .claude/skills/wisecat-tune/scripts/run.sh`.
STRATEGY_WEIGHTS_BY_HORIZON: dict[str, dict[str, float]] = {
    "1W": {
        "trend_50_200":     0.25,
        "ts_momentum_12_1": 0.50,
        "fast_trend_5_20":  0.25,
    },
    "1M": {
        "trend_50_200":     0.45,
        "ts_momentum_12_1": 0.45,
        "fast_trend_5_20":  0.10,
    },
    "1Y": {
        "trend_50_200":     0.55,
        "ts_momentum_12_1": 0.45,
        "fast_trend_5_20":  0.00,
    },
}

# Legacy alias — the 1M weights ARE the canonical "default horizon". Anything
# in the codebase that reads STRATEGY_WEIGHTS gets the 1M view.
STRATEGY_WEIGHTS = STRATEGY_WEIGHTS_BY_HORIZON["1M"]
