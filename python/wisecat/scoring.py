"""Compose per-ticker scores from the per-horizon GBM classifiers.

Loads a per-horizon LightGBM classifier from `wisecat/models/gbm_<horizon>.joblib`,
computes the same feature row used at training time, and returns a probability
triple (Buy/Hold/Sell) plus an expected-return estimate. Per-feature
contributions come from LightGBM's built-in `pred_contrib` so the iOS detail
view can render a per-feature breakdown of the verdict.

If a horizon's artifact is missing or feature compute fails, that horizon
emits a neutral verdict (`pHold = 1.0`, `score = 0`, no signals) — the wire
shape stays uniform across success and degraded paths.
"""

from __future__ import annotations

import logging
from pathlib import Path
from threading import Lock

import numpy as np
import pandas as pd

from .features import FeatureContext, compute_all_features
from .models import HorizonScore, StrategyContribution, TickerScore
from .strategies import HORIZONS

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# GBM artifact loading (lazy, cached). Cold-start cost on Lambda is paid once.
# ---------------------------------------------------------------------------

_MODELS_DIR = Path(__file__).resolve().parent / "models"
_GBM_CACHE: dict[str, dict | None] = {}
_GBM_CACHE_LOCK = Lock()


def _gbm_artifact_path(horizon: str) -> Path:
    return _MODELS_DIR / f"gbm_{horizon}.joblib"


def _load_gbm_artifact(horizon: str) -> dict | None:
    """Return the artifact dict for a horizon, or None if it's not on disk
    or fails to load. Cached after first attempt; no retries on the same
    horizon within a process."""
    with _GBM_CACHE_LOCK:
        if horizon in _GBM_CACHE:
            return _GBM_CACHE[horizon]
        path = _gbm_artifact_path(horizon)
        artifact: dict | None = None
        if path.exists():
            try:
                import joblib
                artifact = joblib.load(path)
            except Exception as e:
                logger.warning("failed to load GBM artifact %s: %s", path, e)
                artifact = None
        _GBM_CACHE[horizon] = artifact
        return artifact


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------


def score_ticker(
    ticker: str,
    df: pd.DataFrame,
    price: float | None,
    context: FeatureContext | None = None,
) -> TickerScore:
    """Score a ticker across all horizons via the per-horizon GBM models.

    Per-horizon: load artifact, compute features once, run GBM. If the
    artifact is missing OR feature compute / pred_contrib raises, that
    horizon falls back to a neutral verdict so a single bad horizon never
    500's the whole response.
    """
    if df.empty:
        return TickerScore(
            ticker=ticker,
            price=price,
            horizons={h: _neutral_horizon() for h in HORIZONS},
            error="no historical data",
        )

    ctx = context or FeatureContext()
    feats: dict[str, float] | None = None
    horizons: dict[str, HorizonScore] = {}
    for horizon in HORIZONS:
        artifact = _load_gbm_artifact(horizon)
        if artifact is None:
            horizons[horizon] = _neutral_horizon()
            continue
        try:
            if feats is None:
                feats = compute_all_features(ticker, df, ctx)
            horizons[horizon] = _score_one_horizon_gbm(artifact, feats)
        except Exception as e:
            logger.warning(
                "GBM scoring failed for %s @ %s, emitting neutral: %s",
                ticker, horizon, e,
            )
            horizons[horizon] = _neutral_horizon()

    return TickerScore(ticker=ticker, price=price, horizons=horizons)


# ---------------------------------------------------------------------------
# GBM path (per-horizon — one model can ship at a time)
# ---------------------------------------------------------------------------


def _score_one_horizon_gbm(artifact: dict, feats: dict[str, float]) -> HorizonScore:
    """Apply one horizon's GBM model to the feature row.

    Returns a HorizonScore with `signals` populated from LightGBM's
    `pred_contrib` so the iOS detail view can render a per-feature
    breakdown of the verdict.
    """
    feature_names: list[str] = artifact["features"]
    booster = artifact["model"]
    label_thresholds: dict[str, float] = artifact.get(
        "label_thresholds", {"buy": 0.05, "sell": 0.05}
    )
    encoding: dict[str, int] = artifact.get(
        "label_encoding", {"Sell": 0, "Hold": 1, "Buy": 2}
    )

    row = np.asarray(
        [[float(feats.get(name, 0.0)) for name in feature_names]], dtype=float
    )
    proba = booster.predict(row)
    if proba.ndim == 1:
        # Binary fallback path — promote to a 3-class shape with Hold = 0.
        # Shouldn't fire for the multiclass training config but defensive.
        proba_3 = np.array([[1.0 - proba[0], 0.0, proba[0]]])
    else:
        proba_3 = proba

    sell_idx = encoding["Sell"]
    hold_idx = encoding["Hold"]
    buy_idx = encoding["Buy"]

    p_sell = float(proba_3[0][sell_idx])
    p_hold = float(proba_3[0][hold_idx])
    p_buy = float(proba_3[0][buy_idx])

    # Expected forward return = E[r] under the trained label thresholds.
    # Centerpoint estimate: Buy class -> +buy_thr, Sell -> -sell_thr,
    # Hold -> 0. Cheap, monotone, easy for the UI to display alongside
    # the probability bar.
    buy_thr = float(label_thresholds.get("buy", 0.05))
    sell_thr = float(label_thresholds.get("sell", 0.05))
    expected_return = (p_buy * buy_thr) - (p_sell * sell_thr)

    # Map back into the legacy [-1, +1] score so anything still reading
    # `score` gets a directionally-correct continuous value.
    composite = max(-1.0, min(1.0, p_buy - p_sell))

    # ------------------------------------------------------------------
    # Per-feature contributions via LightGBM's built-in pred_contrib.
    #
    # pred_contrib is in LOGIT-space, not probability space, and for
    # multiclass returns a flat row of shape (1, n_classes * (n_features + 1)).
    # The layout is class-major: indices [i*(nf+1) : i*(nf+1)+nf] are
    # class i's per-feature contributions, and [i*(nf+1)+nf] is class i's
    # bias term (which we drop).
    #
    # The directional signal we surface = Buy_logit_contrib - Sell_logit_contrib.
    # Positive => the feature pushed the verdict toward Buy at this row;
    # negative => toward Sell. We then keep the top-K by |directional| and
    # report `weight = |directional| / sum_top_K(|directional|)` so weights
    # within the displayed slice sum to 1.0. Note: this weight is a per-row
    # display weight, NOT a static feature importance.
    # ------------------------------------------------------------------
    contributions: list[StrategyContribution] = []
    try:
        contribs = booster.predict(row, pred_contrib=True)
        contribs_row = np.asarray(contribs)[0]
        nf = len(feature_names)
        stride = nf + 1  # +1 for per-class bias
        if contribs_row.size >= stride * (max(buy_idx, sell_idx) + 1):
            buy_contribs = contribs_row[buy_idx * stride : buy_idx * stride + nf]
            sell_contribs = contribs_row[sell_idx * stride : sell_idx * stride + nf]
            directional = buy_contribs - sell_contribs
            # Top-K by absolute directional contribution.
            top_k = min(8, nf)
            order = np.argsort(np.abs(directional))[::-1][:top_k]
            denom = float(np.sum(np.abs(directional[order])))
            for j in order:
                d = float(directional[j])
                w = (abs(d) / denom) if denom > 0 else 0.0
                contributions.append(
                    StrategyContribution(
                        name=feature_names[j],
                        value=float(feats.get(feature_names[j], 0.0)),
                        contribution=d,
                        weight=w,
                    )
                )
    except Exception as e:
        # If pred_contrib fails for any reason, fall back to no signals
        # rather than failing the whole horizon. Probabilities are still
        # the load-bearing output; signals are an explanation layer.
        logger.warning("pred_contrib failed (signals will be empty): %s", e)
        contributions = []

    return HorizonScore(
        score=composite,
        p_buy=p_buy,
        p_hold=p_hold,
        p_sell=p_sell,
        expected_return=expected_return,
        signals=contributions,
    )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _neutral_horizon() -> HorizonScore:
    # All-zero probability triple is a wire-detectable sentinel: real softmax
    # output sums to ~1.0, so (0, 0, 0) cannot occur from a successful GBM
    # prediction. Downstream readers map this to Hold + zero conviction
    # rather than misreading the Pydantic default (pHold=1.0) as a confident
    # "fully Hold" verdict.
    return HorizonScore(
        score=0.0,
        p_buy=0.0,
        p_hold=0.0,
        p_sell=0.0,
        expected_return=0.0,
        signals=[],
    )
