from .mean_reversion import score as mean_reversion_score
from .momentum import score as momentum_score
from .trend import score as trend_score
from .ts_momentum import score as ts_momentum_score
from .volume import score as volume_score

ALL_STRATEGIES = [
    ("trend_50_200", trend_score),
    ("rsi_14", momentum_score),
    ("bollinger_pctb", mean_reversion_score),
    ("volume_confirm", volume_score),
    ("ts_momentum_12_1", ts_momentum_score),
]

# Per-strategy weights in the composite. Weights MUST sum to 1.0.
#
# Trend-following and 12-1 time-series momentum are the only two strategies
# that show meaningfully positive hit rate vs. coin-flip in our SPY
# 2010–2026 backtest (54.2% and 55.1% respectively, n≈4100). The three
# mean-reversion / short-horizon strategies hit at 48-49%, slightly worse
# than chance, so they're down-weighted to a fifth of the trend pillars.
# This skew was an evidence-based choice, not a guess — see the backtest
# results in the v1 commit for the data behind these numbers.
STRATEGY_WEIGHTS = {
    "trend_50_200": 0.35,
    "ts_momentum_12_1": 0.35,
    "rsi_14": 0.10,
    "bollinger_pctb": 0.10,
    "volume_confirm": 0.10,
}
