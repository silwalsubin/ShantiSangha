"""Train per-horizon LightGBM Buy/Hold/Sell classifiers.

Phase 1 of the scoring roadmap (see SCORING_ROADMAP.md). This module
owns the TRAINING side only — it builds the feature matrix, labels rows
by forward return, runs walk-forward CV with embargo, fits one
LGBMClassifier per horizon, and persists the artifact to
`python/wisecat/models/gbm_<horizon>.joblib`.

Scoring (the inference path that loads the persisted artifact and
returns probabilities) lives in `scoring.py` and is intentionally NOT
modified by this module.

CLI:
    python -m wisecat.train --horizons 1W 1M 1Y
    python -m wisecat.train --horizons 1M --tickers AAPL MSFT NVDA --limit 5
"""

from __future__ import annotations

import argparse
import datetime as _dt
import logging
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd

from .features import FeatureContext, compute_all_features

logger = logging.getLogger(__name__)


# Native forward window per horizon (trading days). Mirrors
# tune_basket.NATIVE_WINDOW so train and tune agree on the diagonal.
HORIZON_WINDOWS: dict[str, int] = {"1W": 5, "1M": 21, "1Y": 252}

# Default Buy/Sell thresholds per horizon. Derived from the rough scale
# of forward returns at each window — bigger windows tolerate bigger
# moves before the call counts as decisive.
DEFAULT_LABEL_THRESHOLDS: dict[str, dict[str, float]] = {
    "1W": {"buy": 0.025, "sell": 0.025},
    "1M": {"buy": 0.05, "sell": 0.05},
    "1Y": {"buy": 0.15, "sell": 0.15},
}

# Class encoding: 0 = Sell, 1 = Hold, 2 = Buy. Kept stable across the
# saved artifact so scoring.py doesn't have to map labels at load time.
LABEL_SELL = 0
LABEL_HOLD = 1
LABEL_BUY = 2
LABEL_NAMES = {LABEL_SELL: "Sell", LABEL_HOLD: "Hold", LABEL_BUY: "Buy"}

# Walk-forward CV defaults.
DEFAULT_TRAIN_WINDOW = 504   # ~2 trading years
DEFAULT_EVAL_WINDOW = 63     # ~3 months
DEFAULT_EMBARGO = 21         # gap between train end and eval start

# Minimum trailing bars before we'll compute features for a row. The
# 12-1 momentum strategy needs 274; we round up to 300 to leave a small
# buffer and to make the threshold easy to remember.
MIN_TRAILING_BARS = 300


PACKAGE_DIR = Path(__file__).resolve().parent
DATA_CACHE_DIR = PACKAGE_DIR / "data"
MODELS_DIR = PACKAGE_DIR / "models"
DEFAULT_BASKET = DATA_CACHE_DIR / "nasdaq100.txt"


# ---------------------------------------------------------------------------
# Data loading + caching
# ---------------------------------------------------------------------------


def _cache_path(ticker: str) -> Path:
    return DATA_CACHE_DIR / f"cache_{ticker.upper()}.parquet"


def _load_or_fetch_history(ticker: str, allow_network: bool = True) -> pd.DataFrame:
    """Returns daily OHLCV for `ticker`. Reads from a local parquet cache
    first; only calls yfinance if the cache is missing AND
    `allow_network=True`. Tests run with `allow_network=False`."""
    cache = _cache_path(ticker)
    if cache.exists():
        try:
            df = pd.read_parquet(cache)
            return _normalize_history(df)
        except Exception as e:
            logger.warning("cache read failed for %s (%s); refetching", ticker, e)

    if not allow_network:
        raise FileNotFoundError(
            f"no cached history for {ticker} at {cache} and network fetch disabled"
        )

    # Network fetch is opt-in. Imports are deferred so test environments
    # don't pay for the yfinance import chain.
    from .yfinance_client import get_full_history

    df = get_full_history(ticker)
    DATA_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    df.to_parquet(cache, index=False)
    return _normalize_history(df)


def _normalize_history(df: pd.DataFrame) -> pd.DataFrame:
    """Coerce a freshly-loaded history DataFrame into the shape the rest
    of the pipeline expects: ascending `date`, fully-typed numeric OHLCV,
    no duplicate dates, default RangeIndex."""
    df = df.copy()
    if "date" not in df.columns:
        raise ValueError("history DataFrame missing 'date' column")
    df["date"] = pd.to_datetime(df["date"]).dt.date
    df = df.drop_duplicates(subset="date").sort_values("date").reset_index(drop=True)
    for col in ("open", "high", "low", "close"):
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    if "volume" in df.columns:
        df["volume"] = pd.to_numeric(df["volume"], errors="coerce").fillna(0).astype("int64")
    return df


def _load_basket(path: Path) -> list[str]:
    out: list[str] = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        ticker = line.split()[0].upper()
        if ticker:
            out.append(ticker)
    return out


# ---------------------------------------------------------------------------
# Dataset construction
# ---------------------------------------------------------------------------


def _label_from_forward_return(
    fwd_ret: float, buy_thr: float, sell_thr: float
) -> int:
    if fwd_ret >= buy_thr:
        return LABEL_BUY
    if fwd_ret <= -sell_thr:
        return LABEL_SELL
    return LABEL_HOLD


def build_dataset(
    tickers: Iterable[str],
    horizon: str,
    *,
    histories: dict[str, pd.DataFrame] | None = None,
    label_thresholds: dict[str, float] | None = None,
    context: FeatureContext | None = None,
    min_trailing_bars: int = MIN_TRAILING_BARS,
    allow_network: bool = False,
    progress: bool = False,
) -> tuple[pd.DataFrame, np.ndarray, np.ndarray]:
    """Walk every (ticker, date) pair with enough trailing history and
    return (X, y, decision_dates).

    X: float DataFrame, one row per (ticker, decision_date), columns are
       feature names in the order produced by `compute_all_features`.
    y: int array of class labels (0=Sell, 1=Hold, 2=Buy).
    decision_dates: numpy array of `numpy.datetime64[D]` matching X rows
                    — needed for walk-forward splits.

    Pass `histories` to inject pre-loaded bars (used by tests). Otherwise
    each ticker is loaded via `_load_or_fetch_history`.
    """
    if horizon not in HORIZON_WINDOWS:
        raise ValueError(f"unknown horizon {horizon!r}; expected one of {list(HORIZON_WINDOWS)}")
    window = HORIZON_WINDOWS[horizon]
    thr = label_thresholds or DEFAULT_LABEL_THRESHOLDS[horizon]
    buy_thr = float(thr["buy"])
    sell_thr = float(thr["sell"])

    ctx = context or FeatureContext()

    feature_rows: list[dict[str, float]] = []
    labels: list[int] = []
    dates: list[_dt.date] = []
    tickers_col: list[str] = []

    for ticker in tickers:
        if histories is not None and ticker in histories:
            df = _normalize_history(histories[ticker])
        else:
            try:
                df = _load_or_fetch_history(ticker, allow_network=allow_network)
            except Exception as e:
                logger.warning("skipping %s: %s", ticker, e)
                continue

        if len(df) < min_trailing_bars + window + 1:
            logger.info("skipping %s: only %d bars", ticker, len(df))
            continue

        closes = df["close"].to_numpy(dtype=float)
        ticker_dates = df["date"].to_numpy()
        last_decision_idx = len(df) - window - 1

        for i in range(min_trailing_bars - 1, last_decision_idx + 1):
            cur_close = closes[i]
            fwd_close = closes[i + window]
            if cur_close <= 0 or not np.isfinite(cur_close) or not np.isfinite(fwd_close):
                continue
            fwd_ret = float(fwd_close / cur_close - 1.0)
            slice_df = df.iloc[: i + 1]
            try:
                feats = compute_all_features(ticker, slice_df, ctx)
            except Exception as e:
                logger.warning("feature compute failed at %s %s: %s",
                               ticker, ticker_dates[i], e)
                continue
            feature_rows.append(feats)
            labels.append(_label_from_forward_return(fwd_ret, buy_thr, sell_thr))
            dates.append(ticker_dates[i])
            tickers_col.append(ticker)

        if progress:
            print(f"  · {ticker}: built {len(labels)} cumulative rows", file=sys.stderr)

    if not feature_rows:
        raise ValueError("no rows built — check tickers / histories / min_trailing_bars")

    X = pd.DataFrame(feature_rows).fillna(0.0)
    y = np.asarray(labels, dtype=np.int64)
    # Store as datetime64[D] for clean comparisons in walk-forward splits.
    dates_arr = np.asarray([np.datetime64(d, "D") for d in dates])
    X.attrs["tickers"] = tickers_col
    return X, y, dates_arr


# ---------------------------------------------------------------------------
# Walk-forward CV
# ---------------------------------------------------------------------------


@dataclass
class FoldMetrics:
    fold: int
    train_start: _dt.date
    train_end: _dt.date
    eval_start: _dt.date
    eval_end: _dt.date
    n_train: int
    n_eval: int
    accuracy: float
    per_class: dict[int, dict[str, float]]


def _walk_forward_splits(
    dates: np.ndarray,
    train_window: int,
    eval_window: int,
    embargo: int,
) -> list[tuple[np.ndarray, np.ndarray]]:
    """Yield (train_idx, eval_idx) pairs over unique dates.

    Walk-forward: train on `train_window` consecutive unique dates, skip
    `embargo` dates, evaluate on the next `eval_window` dates, then
    advance by `eval_window`. Embargo prevents label leakage from the
    overlapping forward-return windows used to label rows.
    """
    unique_dates = np.unique(dates)
    splits: list[tuple[np.ndarray, np.ndarray]] = []
    n = len(unique_dates)
    start = 0
    while True:
        train_end = start + train_window
        eval_start = train_end + embargo
        eval_end = eval_start + eval_window
        if eval_end > n:
            break
        train_lo = unique_dates[start]
        train_hi = unique_dates[train_end - 1]
        eval_lo = unique_dates[eval_start]
        eval_hi = unique_dates[eval_end - 1]
        train_mask = (dates >= train_lo) & (dates <= train_hi)
        eval_mask = (dates >= eval_lo) & (dates <= eval_hi)
        if train_mask.any() and eval_mask.any():
            splits.append((np.flatnonzero(train_mask), np.flatnonzero(eval_mask)))
        start += eval_window
    return splits


def _per_class_precision_recall(
    y_true: np.ndarray, y_pred: np.ndarray, classes: Iterable[int]
) -> dict[int, dict[str, float]]:
    """Lightweight stand-in for sklearn.metrics.classification_report —
    computes precision and recall per class without depending on sklearn.
    """
    out: dict[int, dict[str, float]] = {}
    for c in classes:
        tp = int(((y_pred == c) & (y_true == c)).sum())
        fp = int(((y_pred == c) & (y_true != c)).sum())
        fn = int(((y_pred != c) & (y_true == c)).sum())
        precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        out[int(c)] = {"precision": precision, "recall": recall, "support": tp + fn}
    return out


def _balanced_class_weights(y: np.ndarray) -> dict[int, float]:
    """sklearn.utils.class_weight.compute_class_weight('balanced') without
    pulling sklearn in. Weight = n_samples / (n_classes * count(class))."""
    counts = Counter(int(c) for c in y)
    n = len(y)
    n_classes = len(counts)
    if n == 0 or n_classes == 0:
        return {}
    return {c: n / (n_classes * cnt) for c, cnt in counts.items()}


# ---------------------------------------------------------------------------
# Training
# ---------------------------------------------------------------------------


_LGB_PARAMS = {
    "objective": "multiclass",
    "num_class": 3,
    "learning_rate": 0.05,
    "num_leaves": 31,
    "min_data_in_leaf": 200,
    "verbosity": -1,
    "num_threads": 0,  # 0 = all available
}
_LGB_NUM_BOOST_ROUND = 300


def _train_booster(
    X: np.ndarray, y: np.ndarray, class_weight: dict[int, float] | None,
):
    """Train a multiclass LightGBM booster on (X, y) using the native API.

    We deliberately use `lgb.train` instead of `LGBMClassifier` — the
    sklearn-style wrapper imports sklearn at fit time, which we don't
    require elsewhere in the project. Class imbalance is handled via
    per-row sample weights (the native equivalent of the sklearn wrapper's
    `class_weight=` argument).
    """
    import lightgbm as lgb

    if class_weight:
        sample_weight = np.array(
            [class_weight.get(int(c), 1.0) for c in y], dtype=float
        )
    else:
        sample_weight = None

    dataset = lgb.Dataset(X, label=y, weight=sample_weight, free_raw_data=False)
    return lgb.train(
        params=_LGB_PARAMS,
        train_set=dataset,
        num_boost_round=_LGB_NUM_BOOST_ROUND,
    )


def _booster_predict_class(booster, X: np.ndarray) -> np.ndarray:
    """Run the booster's multiclass predict and reduce to class indices."""
    proba = booster.predict(X)
    if proba.ndim == 1:
        # Defensive: shouldn't happen for multiclass with num_class=3, but
        # keeps the call site simple if upstream LightGBM ever changes.
        return (proba >= 0.5).astype(np.int64)
    return np.argmax(proba, axis=1).astype(np.int64)


def train_one_horizon(
    X: pd.DataFrame,
    y: np.ndarray,
    dates: np.ndarray,
    horizon: str,
    *,
    label_thresholds: dict[str, float] | None = None,
    train_window: int = DEFAULT_TRAIN_WINDOW,
    eval_window: int = DEFAULT_EVAL_WINDOW,
    embargo: int = DEFAULT_EMBARGO,
) -> dict:
    """Run walk-forward CV, then refit on all data for the persisted
    artifact. Returns the artifact dict ready for `save_model_artifact`.
    """
    if horizon not in HORIZON_WINDOWS:
        raise ValueError(f"unknown horizon {horizon!r}")
    if len(X) != len(y) or len(X) != len(dates):
        raise ValueError("X, y, dates must be the same length")

    feature_names = list(X.columns)
    X_arr = X.to_numpy(dtype=float)
    classes = (LABEL_SELL, LABEL_HOLD, LABEL_BUY)
    cw = _balanced_class_weights(y)

    splits = _walk_forward_splits(dates, train_window, eval_window, embargo)
    fold_metrics: list[FoldMetrics] = []
    for fold_i, (train_idx, eval_idx) in enumerate(splits):
        booster = _train_booster(X_arr[train_idx], y[train_idx], cw)
        y_pred = _booster_predict_class(booster, X_arr[eval_idx])
        accuracy = float((y_pred == y[eval_idx]).mean()) if len(eval_idx) else 0.0
        per_class = _per_class_precision_recall(y[eval_idx], y_pred, classes)
        fold_metrics.append(
            FoldMetrics(
                fold=fold_i,
                train_start=pd.to_datetime(dates[train_idx].min()).date(),
                train_end=pd.to_datetime(dates[train_idx].max()).date(),
                eval_start=pd.to_datetime(dates[eval_idx].min()).date(),
                eval_end=pd.to_datetime(dates[eval_idx].max()).date(),
                n_train=int(len(train_idx)),
                n_eval=int(len(eval_idx)),
                accuracy=accuracy,
                per_class=per_class,
            )
        )

    # Refit on the full dataset for the persisted artifact. Walk-forward
    # CV above is the honest out-of-sample estimate; the final fit uses
    # everything so the model deployed sees the most recent data.
    final = _train_booster(X_arr, y, cw)

    artifact = {
        "model": final,
        "features": feature_names,
        "horizon": horizon,
        "label_thresholds": dict(label_thresholds or DEFAULT_LABEL_THRESHOLDS[horizon]),
        "label_encoding": {"Sell": LABEL_SELL, "Hold": LABEL_HOLD, "Buy": LABEL_BUY},
        "trained_at": _dt.datetime.now(_dt.timezone.utc).isoformat(),
        "n_rows": int(len(X)),
        "class_weights": cw,
        "cv": {
            "train_window": train_window,
            "eval_window": eval_window,
            "embargo": embargo,
            "n_folds": len(fold_metrics),
            "fold_metrics": [fm.__dict__ for fm in fold_metrics],
            "mean_accuracy": float(np.mean([fm.accuracy for fm in fold_metrics]))
            if fold_metrics else 0.0,
        },
    }
    return artifact


def save_model_artifact(artifact: dict, path: Path) -> Path:
    """Persist the artifact via joblib. Returns the path written."""
    import joblib

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(artifact, path)
    return path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _print_horizon_report(horizon: str, artifact: dict) -> None:
    cv = artifact["cv"]
    print()
    print(f"=== Horizon {horizon} ===")
    print(f"Rows: {artifact['n_rows']}, features: {len(artifact['features'])}")
    print(f"Folds: {cv['n_folds']} (train={cv['train_window']}d, "
          f"eval={cv['eval_window']}d, embargo={cv['embargo']}d)")
    print(f"Mean OOS accuracy: {cv['mean_accuracy']:.3f}")
    if cv["fold_metrics"]:
        avg_per_class: dict[int, dict[str, float]] = {c: {"precision": 0.0, "recall": 0.0}
                                                       for c in (LABEL_SELL, LABEL_HOLD, LABEL_BUY)}
        for fm in cv["fold_metrics"]:
            for c, m in fm["per_class"].items():
                avg_per_class[int(c)]["precision"] += m["precision"]
                avg_per_class[int(c)]["recall"] += m["recall"]
        n = len(cv["fold_metrics"])
        print(f"  {'class':6} {'precision':>10} {'recall':>10}")
        for c, name in LABEL_NAMES.items():
            p = avg_per_class[c]["precision"] / n
            r = avg_per_class[c]["recall"] / n
            print(f"  {name:6} {p:>10.3f} {r:>10.3f}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Train per-horizon LightGBM Buy/Hold/Sell classifiers."
    )
    parser.add_argument(
        "--horizons",
        nargs="+",
        default=["1W", "1M", "1Y"],
        choices=list(HORIZON_WINDOWS),
        help="Which horizons to train.",
    )
    parser.add_argument(
        "--tickers",
        nargs="+",
        default=None,
        help="Override basket. If omitted, uses data/nasdaq100.txt.",
    )
    parser.add_argument(
        "--basket",
        type=Path,
        default=DEFAULT_BASKET,
        help="Path to basket file (one ticker per line).",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Train on the first N tickers only — for fast iteration.",
    )
    parser.add_argument(
        "--allow-network",
        action="store_true",
        help="Permit yfinance fetches when a ticker isn't cached.",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=MODELS_DIR,
        help="Directory to write gbm_<horizon>.joblib into.",
    )
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(message)s")

    if args.tickers:
        tickers = [t.upper() for t in args.tickers]
    else:
        tickers = _load_basket(args.basket)
    if args.limit:
        tickers = tickers[: args.limit]
    if not tickers:
        print("no tickers to train on", file=sys.stderr)
        return 2

    # Bootstrap the cross-sectional / regime context once. With
    # --allow-network this also writes the SPY + VIX parquet cache that
    # the Lambda image consumes at inference time.
    from .context_loaders import load_default_context
    ctx = load_default_context(allow_network=args.allow_network)
    populated = []
    if ctx.spy_history is not None:
        populated.append("SPY")
    if ctx.vix_history is not None:
        populated.append("VIX")
    if populated:
        print(f"FeatureContext loaded: {', '.join(populated)}", file=sys.stderr)
    else:
        print("FeatureContext empty — only base technicals will contribute. "
              "Pass --allow-network to bootstrap the SPY + VIX cache.",
              file=sys.stderr)

    for horizon in args.horizons:
        print(f"\nBuilding dataset for {horizon} on {len(tickers)} tickers…",
              file=sys.stderr)
        X, y, dates = build_dataset(
            tickers,
            horizon=horizon,
            allow_network=args.allow_network,
            context=ctx,
            progress=True,
        )
        artifact = train_one_horizon(X, y, dates, horizon=horizon)
        out_path = args.out_dir / f"gbm_{horizon}.joblib"
        save_model_artifact(artifact, out_path)
        _print_horizon_report(horizon, artifact)
        print(f"  wrote {out_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
