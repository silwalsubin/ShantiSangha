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
