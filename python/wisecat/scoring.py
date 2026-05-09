"""Compose per-ticker scores from individual strategies.

Two scoring paths live side by side:

- **Legacy**: weighted sum of registered strategies, fanned out to per-horizon
  weights from `STRATEGY_WEIGHTS_BY_HORIZON`. The composite is the long-running
  scoring engine that ships today. Always emits the new `pBuy/pHold/pSell/
  expectedReturn` fields with neutral defaults (`p_hold = 1.0`) so the wire
  format is uniform across both paths.

- **GBM**: Phase 1 of SCORING_ROADMAP.md. Loads a per-horizon LightGBM
  classifier from `wisecat/models/gbm_<horizon>.joblib`, computes the same
  feature row used at training time, returns probability triples + an
  expected-return estimate. Activated only when `WISECAT_GBM_ENABLED=1` AND
  every requested horizon has a model artifact on disk; otherwise falls back
  to legacy. Lets us A/B against the legacy path before retiring it.
"""

from __future__ import annotations

import logging
import os
from pathlib import Path
from threading import Lock

import numpy as np
import pandas as pd

from .features import FeatureContext, compute_all_features
from .models import HorizonScore, StrategyContribution, TickerScore
from .strategies import ALL_STRATEGIES, HORIZONS, STRATEGY_WEIGHTS_BY_HORIZON

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# GBM artifact loading (lazy, cached). Cold-start cost on Lambda is paid once.
# ---------------------------------------------------------------------------

_MODELS_DIR = Path(__file__).resolve().parent / "models"
_GBM_CACHE: dict[str, dict | None] = {}
_GBM_CACHE_LOCK = Lock()


def _gbm_enabled() -> bool:
    return os.environ.get("WISECAT_GBM_ENABLED", "").strip() in ("1", "true", "True", "yes")


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


def _all_horizons_have_models(horizons: tuple[str, ...]) -> bool:
    return all(_load_gbm_artifact(h) is not None for h in horizons)


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------


def score_ticker(
    ticker: str,
    df: pd.DataFrame,
    price: float | None,
    context: FeatureContext | None = None,
) -> TickerScore:
    """Score a ticker across all horizons.

    Routes to the GBM path when enabled AND every horizon has a trained
    artifact; otherwise the legacy weighted-sum path. Both paths return
    a fully populated `TickerScore` with the same wire shape.
    """
    if df.empty:
        return TickerScore(
            ticker=ticker,
            price=price,
            horizons={h: _neutral_horizon([]) for h in HORIZONS},
            error="no historical data",
        )

    if _gbm_enabled() and _all_horizons_have_models(HORIZONS):
        try:
            return _score_gbm(ticker, df, price, context or FeatureContext())
        except Exception as e:
            # GBM path failures fall back to legacy rather than 500'ing the
            # Lambda — neutral prob fields still ship a usable signal.
            logger.warning("GBM scoring failed for %s, falling back: %s", ticker, e)

    return _score_legacy(ticker, df, price)


# ---------------------------------------------------------------------------
# Legacy weighted-sum path
# ---------------------------------------------------------------------------


def _score_legacy(ticker: str, df: pd.DataFrame, price: float | None) -> TickerScore:
    """Compute every strategy's (raw, value) once, fan out to per-horizon
    weights. Fills probabilistic fields with neutral defaults so the wire
    format matches the GBM path."""
    strategy_results: dict[str, tuple[float, float]] = {}
    for name, strategy_fn in ALL_STRATEGIES:
        try:
            raw, value = strategy_fn(df)
        except Exception as e:
            logger.warning("strategy %s failed for %s: %s", name, ticker, e)
            continue
        strategy_results[name] = (raw, value)

    horizons: dict[str, HorizonScore] = {}
    for horizon in HORIZONS:
        weights = STRATEGY_WEIGHTS_BY_HORIZON[horizon]
        contributions: list[StrategyContribution] = []
        total = 0.0
        for name, (raw, value) in strategy_results.items():
            weight = weights.get(name, 0.0)
            contributions.append(
                StrategyContribution(
                    name=name,
                    value=raw,
                    contribution=value * weight,
                    weight=weight,
                )
            )
            total += value * weight
        horizons[horizon] = HorizonScore(
            score=total,
            signals=contributions,
            # p_buy / p_hold / p_sell / expected_return default to the
            # neutral verdict — see HorizonScore field defaults.
        )
    return TickerScore(ticker=ticker, price=price, horizons=horizons)


# ---------------------------------------------------------------------------
# GBM path
# ---------------------------------------------------------------------------


def _score_gbm(
    ticker: str,
    df: pd.DataFrame,
    price: float | None,
    context: FeatureContext,
) -> TickerScore:
    """Score via per-horizon LightGBM artifacts. Each horizon's artifact
    carries its own feature list, label thresholds, and class encoding.
    """
    feats = compute_all_features(ticker, df, context)

    horizons: dict[str, HorizonScore] = {}
    for horizon in HORIZONS:
        artifact = _load_gbm_artifact(horizon)
        if artifact is None:
            # Defensive — _all_horizons_have_models() should gate this, but
            # in case of a race with cache invalidation, fall back per horizon.
            horizons[horizon] = _neutral_horizon([])
            continue
        horizons[horizon] = _score_one_horizon_gbm(artifact, feats)

    return TickerScore(ticker=ticker, price=price, horizons=horizons)


def _score_one_horizon_gbm(artifact: dict, feats: dict[str, float]) -> HorizonScore:
    """Apply one horizon's GBM model to the feature row.

    Returns a HorizonScore with `signals = []` for now — feature-importance
    breakdowns (SHAP) are a Phase 4 concern. The legacy `score` field is
    populated with `expected_return` so any consumer still reading it gets
    a sensible continuous value.
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

    return HorizonScore(
        score=composite,
        p_buy=p_buy,
        p_hold=p_hold,
        p_sell=p_sell,
        expected_return=expected_return,
        signals=[],
    )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _neutral_horizon(signals: list[StrategyContribution]) -> HorizonScore:
    return HorizonScore(score=0.0, signals=signals)
