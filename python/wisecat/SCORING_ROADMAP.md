# WiseCat scoring roadmap

Plan for evolving the Stocks Buy/Hold/Sell verdict from a hand-weighted
sum of three trend-following technicals into a calibrated, regime-aware
classifier. Authored 2026-05-08.

## Where the system is today

- **3 strategies, all price-based, all trend-following**: `trend_50_200`,
  `ts_momentum_12_1`, `fast_trend_5_20`. They agree ~80% of the time and
  disagree only at turning points.
- **Linear weighting** with static per-horizon weights ([strategies/__init__.py](strategies/__init__.py)).
- **Tuned by hit rate** on a basket backtest at each horizon's native
  forward window ([tune_basket.py](tune_basket.py)).
- **Output**: a single composite score in [-1, +1] mapped to Buy/Hold/Sell
  via fixed thresholds (±0.5) — same thresholds for every ticker, every
  regime.
- **Refresh cadence**: once daily at 8:15 PM UTC via Hangfire
  (`GenerateDailyTradingSignalsJob`). Score is frozen until next close.

### Where this caps out

- Linear weights cannot capture interactions ("trend works only when vol
  is calm"). Adding more correlated price signals hits diminishing returns
  fast.
- Hit-rate-of-a-score is not the metric users care about. Buy/Hold/Sell
  classification accuracy on forward returns is.
- Static thresholds treat NVDA at +0.5 the same as KO at +0.5 — wrong by
  a factor of vol.
- The basket evaluates on the same window weights are derived from →
  overfitting trap as feature count grows.
- Backtest universe (current NASDAQ-100 / S&P 500 constituents) inflates
  apparent returns 2–3% via survivorship bias.

## Phased plan

Each phase ends in a state where the system is shipped, working, and
strictly better than before. No "Phase 4 unlocks Phase 1's value" coupling.

### Phase 1 — Model upgrade (the structural win)

**Goal**: replace `scoring.py`'s weighted sum with a LightGBM classifier
that outputs a probability distribution over {Buy, Hold, Sell}.

**Why this first**: a few percentage points of classification accuracy
for the same features, and probabilistic output unlocks every Phase 4
UX change.

**Tasks**:
1. Add `lightgbm` to `wisecat/requirements.txt`.
2. Define training labels: forward 5d / 21d / 252d return → {Sell ≤ -3%,
   Hold, Buy ≥ +3%}. Per-horizon thresholds tuned from realized return
   distributions, not pulled from thin air.
3. Build training dataset: existing strategies become *features*, not
   mini-models. One row per (ticker, date), columns = each strategy's
   raw value + future return label.
4. Train one classifier per horizon (3 models). Cross-validation:
   walk-forward, 252-day train / 63-day eval, rolling.
5. Replace `score_ticker()` body. New return shape:
   `{horizon: {p_buy, p_hold, p_sell, expected_return}}`.
6. Persist trained models alongside the Lambda image (joblib pickle in
   `python/wisecat/models/`). Retrain weekly via a new GitHub Actions
   workflow or a Hangfire job.
7. Backend DTO already has room — wire `pBuy / pHold / pSell` into
   `HorizonReadDto` (additive, doesn't break legacy consumers).

**Files touched**: `scoring.py`, `models.py`, `lambda_handler.py`,
`requirements.txt`, new `train.py`, new `models/` directory.

**Success metric**: forward 21d classification accuracy on a held-out
2024–2026 window. Baseline (current weighted sum mapped to ±0.5
thresholds): TBD — measure before changing anything. Target: +3 pp.

**Estimated effort**: 1 weekend.

### Phase 2 — Calibration & regime awareness

**Goal**: stop pretending one threshold and one model fit every ticker
and every regime.

**Tasks**:
1. **Per-ticker / per-vol-bucket thresholds**. After Phase 1's model
   produces `p_buy`, calibrate the Buy threshold per ticker (or per
   60d realized-vol bucket) to whatever historically produced ≥60%
   forward-return hit rate. Persist as a per-ticker config.
2. **VIX as a feature**. Pull VIX history (yfinance `^VIX`) once per
   training run. Add VIX level + VIX 21d change as features. The GBM
   learns regime conditioning without needing two separate models.
3. **Walk-forward CV with embargo** in the training pipeline. 21-day
   embargo between train and eval to prevent label leakage from
   overlapping forward windows.

**Files touched**: `train.py`, `tune_basket.py` (or replace it),
`scoring.py` (threshold lookup), new `python/wisecat/data/vix.py`.

**Success metric**: hold-out accuracy in high-vol periods (VIX > 25)
specifically — current system loses money here.

**Estimated effort**: 2–3 days.

### Phase 3 — Orthogonal feature surface

**Goal**: add information that's actually new — not another EMA cross.

Each feature gets added, retrained, and earns/loses weight via the GBM's
own importance scores. No more hand-tuned weights to debate.

**Features to add**, in order of expected impact:

1. **Cross-sectional rank vs SPY**. Rolling 3M and 6M return spread
   vs SPY. Captures relative momentum. Free (yfinance `SPY`).
2. **Earnings momentum**. 3M change in consensus EPS estimate. Free
   via yfinance / Finnhub. One of the most replicated factors in
   academic finance.
3. **Post-earnings drift (PEAD)**. Days-since-earnings + sign of
   1-day post-earnings reaction. Drift continues 60+ days.
4. **Sector relative strength**. Same as #1 but vs sector ETF
   (XLK, XLF, etc.) — needs a ticker → sector map.
5. **Quality**. Gross profit / total assets (Novy-Marx). Pulled
   quarterly from yfinance fundamentals.
6. **Multi-asset regime features**. TLT/SPY ratio (risk-on/off),
   DXY level + change, HYG (credit). Read once daily.
7. **Calendar features**. Days-to-earnings, days-to-FOMC, day-of-week,
   month-of-year. Each is one column.
8. **Range-position-in-day** (the candle-reading derivative).
   `(close - low) / (high - low)`, averaged 5 days. Continuous, testable,
   captures the actual signal hidden inside hammer/shooting-star folklore.

**Skip**:
- Named candlestick patterns (CDLDOJI etc.). Mostly retail folklore;
  the continuous version (#8) captures what little signal exists.
- Sentiment / social media. Noisy and arbitraged out by retail.
- Deep learning. Tabular low-frequency data → GBM beats DL,
  empirically settled.

**Files touched**: new `wisecat/features/` directory, one file per
feature family. `train.py` registers them.

**Estimated effort**: 1–2 days per feature, parallelizable.

### Phase 4 — UX / output

**Goal**: surface the model's actual uncertainty in the iOS UI. Today's
`+1.00 Buy` implies certainty the system doesn't have.

**Changes** (all unblocked by Phase 1's probabilistic output):

1. **Probability bar** replacing the single conviction arc. Three
   stacked segments (Buy / Hold / Sell) sized by `p_buy / p_hold / p_sell`.
2. **Ensemble disagreement flag**. When 1W / 1M / 1Y verdicts diverge
   (e.g. 1W=Buy, 1Y=Sell), show a "horizons disagree — consider waiting"
   banner. Disagreement IS information; right now it's hidden.
3. **Confidence interval on expected return**. The model can output
   25th/75th percentiles of forward return. Show as a range, not a point.
4. **Position-sizing hint**. Kelly fraction (capped at, say, 25%) or
   vol-targeted weight. "Buy" doesn't mean "all in."
5. **Surface why**. Top 3 features driving each verdict (LightGBM gives
   per-prediction SHAP values for free). Replaces the current static
   weight table with something that actually explains *this* call.

**Files touched**: `WiseCatDetailView.swift`, new shared `ProbabilityBar`
view, DTO additions.

**Estimated effort**: 2–3 days for all five.

### Phase 5 — Survivorship correction (optional, expensive)

Survivorship bias inflates backtest accuracy 2–3 percentage points. The
fix needs point-in-time index membership data — CRSP or similar, which
is paid. Two pragmatic options:

- **Cheap fix**: trust only relative comparisons across configs, never
  absolute hit rates. Document this in basket-tune output.
- **Real fix**: license CRSP via WRDS academic ($, but cheap if you have
  a university affiliation). Reconstruct historical S&P 500 / Nasdaq-100
  membership.

Defer until Phases 1–4 are done; this is an honesty-of-numbers fix, not
a model-quality fix.

## Honest expected gains

Stacked, on the same out-of-sample window:

| Change                                                 | Expected Δ accuracy |
|--------------------------------------------------------|---------------------|
| More features alone (Phase 3, kept in linear weights)  | +2–4 pp             |
| Switch to GBM on current features (Phase 1)            | +3–6 pp             |
| GBM + new features + calibrated thresholds (1+2+3)     | +5–10 pp            |

Past that, on free retail data, you're in diminishing-returns territory.
Further gains require paid data (point-in-time fundamentals, options
flow) and full-time focus.

## What NOT to do

- **Don't add more EMA crosses or RSI variants**. Anything you'd add
  correlates >0.9 with what exists. Real diversity comes from a
  different *category* of information (fundamental, cross-sectional,
  macro), not another window length.
- **Don't ship a deep learning model**. Tabular financial data is
  GBM territory. LSTMs and Transformers consistently lose to
  gradient-boosted trees on this problem class.
- **Don't try to predict next-day moves**. Free retail data is too
  laggy and the noise floor is too high. Stay at 1W+ horizons.
- **Don't bolt on alt-data scrapers**. Twitter sentiment, satellite
  imagery, credit card panels — all expensive to acquire, mostly
  arbitraged out by the time retail sees them.
- **Don't replace the user-facing UI before Phase 1**. The current
  arc gauge is fine for a deterministic score; it stops making sense
  the moment outputs are probabilistic. Sequence matters.

## Recommended starting point

**Phase 1, scoped to one horizon (1M).** Train a single LightGBM
classifier on existing features for the 1M forward return, ship it
behind a `WISECAT_GBM_ENABLED` config flag, run both old and new
in parallel for two weeks, compare 21d hit rates on actual signals
served to users. If GBM wins, expand to 1W + 1Y and retire the
linear weighting. If it doesn't, we've learned something cheap.

That gives a real production signal — "is the model upgrade actually
working on our universe?" — before committing to the full plan.

---

## Implementation status (2026-05-08)

Phase 1 + Phase 3 + Phase 4 component scaffolding shipped this session.
Both scoring paths coexist behind an env flag; the wire format is uniform.

### What shipped

**Phase 1 — training infrastructure**
- [train.py](train.py) — `build_dataset` + `train_one_horizon` + walk-forward CV
  with embargo. Native LightGBM API (`lgb.train` + `lgb.Dataset`); the artifact's
  `"model"` key is a `Booster`, not an `LGBMClassifier` — no sklearn dependency.
  Class encoding is fixed at `Sell=0, Hold=1, Buy=2` and stored in the artifact
  under `"label_encoding"` so scoring loads it without re-deriving.
- Class imbalance handled via per-row `sample_weight` (balanced inverse frequency).
- Walk-forward defaults: 504-day train / 63-day eval / 21-day embargo, slid by
  the eval window each step.
- `lightgbm`, `joblib`, `pyarrow` added to [requirements.txt](requirements.txt).
- Artifacts go to [models/](models/) (`gbm_<horizon>.joblib`). Bundled into the
  Lambda image at build time. **No model trained yet** — that's a follow-up
  cycle (data download + ~minutes of training + commit + deploy).

**Phase 1 — scoring rewrite**
- [scoring.py](scoring.py) carries two paths side by side:
  - **Legacy** — weighted-sum (current shipped behavior, unchanged math).
    Always populates `pHold=1.0`, other p-fields zero, so wire shape is uniform.
  - **GBM** — loads `models/gbm_<horizon>.joblib` lazily on first call (cached
    per-process). Computes features via `compute_all_features`, runs the booster,
    emits `(p_buy, p_hold, p_sell, expected_return)`. Falls back to legacy on
    any failure rather than 500'ing the Lambda.
- Activated only when `WISECAT_GBM_ENABLED=1` AND every horizon has an artifact
  on disk. Lets the Lambda ship without artifacts and degrade gracefully to
  legacy until training catches up.
- [lambda_handler.py](lambda_handler.py) `_serialize_score` emits the new
  per-horizon keys: `pBuy`, `pHold`, `pSell`, `expectedReturn`.
- [models.py](models.py) `HorizonScore` carries the four new fields with
  Pydantic aliases (`p_buy → pBuy` etc.) so internal Python stays snake_case
  and JSON output stays camelCase.

**Phase 3 — feature library**
- [features/](features/) directory with the registered orchestration
  (`compute_all_features`) plus six modules:
  - `base_technicals.py` — re-exports the existing trend / 12-1 momentum /
    fast-trend strategies as `*_raw` + `*_value` features.
  - `cross_sectional.py` — return spread vs SPY at 63d / 126d / 252d.
  - `earnings.py` — `days_since_earnings`, `days_to_earnings`,
    `post_earnings_drift_signal` (1-day reaction × decay).
  - `calendar.py` — `month_of_year`, `day_of_week`, `quarter_end_proximity`,
    `january_effect_flag`.
  - `range_position.py` — close-position-in-range, 5d avg, body/ATR ratio,
    upper/lower wick %.
  - `vix_regime.py` — `vix_level`, `vix_change_21d`, `vix_zscore_252d`.
- Modules return empty dict when their context inputs are missing
  (`spy_history is None`, no earnings dates, etc.) — the orchestrator just
  drops absent keys, downstream pipelines fill NaN with 0.0.

**Phase 4 — UX scaffolding (component built, not yet wired)**
- New `ProbabilityBar.swift` SwiftUI component: three-segment capsule for
  the `(pBuy, pHold, pSell)` triple with sacred-palette colors, animated
  segment transitions, percentage labels with cramping-rule (hide labels
  on segments < 8% width to prevent layout snap).
- Swift `HorizonRead` decodes the new optional fields and exposes
  `hasProbabilisticVerdict` to gate UI on real distributions vs. legacy
  defaults.
- **Not wired into `WiseCatDetailView`** — that's a deliberate hold until
  the model is trained and serving real probabilities. Wiring the bar in
  on top of the legacy `pHold=1.0` defaults would render an all-grey bar
  and confuse users.

**Backend — additive plumbing**
- 12 new columns on `TradingSignal` (`PBuy/PHold/PSell/ExpectedReturn` per
  horizon). PHold defaults to 1.0 so legacy rows read as "fully Hold" in
  the new fields.
- Migration `20260508130000_AddTradingSignalProbabilities` (idempotent
  raw SQL).
- `HorizonReadDto` extended with the four fields. Top-level
  `TradingSignalDto` deliberately untouched — per-horizon reads carry the
  data; no need to bloat the legacy 1M-mirror at the top level.
- `MarketDataClient.ToHorizonScore` deserializes the new wire keys with
  neutral defaults when missing.

### What's pending

- **Train an actual model.** Run `python -m wisecat.train --horizons 1M
  --tickers <basket>` against ~500 NASDAQ-100 + S&P 500 names with at
  least 5 years of history. Commit the resulting `models/gbm_1M.joblib`,
  rebuild the Lambda image, set `WISECAT_GBM_ENABLED=1` in the Lambda
  environment.
- **Populate `FeatureContext`.** Today both training and inference run
  with an empty `FeatureContext()` — only `base_technicals` actually
  produces features. The cross-sectional / earnings / VIX feature
  modules are wired up structurally, but won't contribute until the
  context loaders ship (yfinance bulk pull for SPY/VIX, Finnhub earnings
  pull for the universe).
- **A/B measurement.** No dashboard yet to compare GBM vs. legacy hit
  rates on actual user signals. Add a side-by-side log line in
  `TradingSignalService.GenerateAsync` once both paths produce real
  output, then compare manually after two weeks.
- **Phase 2** — calibrated thresholds, regime conditioning beyond the
  VIX feature, walk-forward CV in production retraining cron.
- **Phase 4 — UI integration.** Swap the conviction arc for the
  `ProbabilityBar` in `WiseCatDetailView` once the GBM is producing real
  distributions. Until then, keep the arc — it's accurate for the
  weighted-sum composite.

### Honest caveats from the build

- **No FeatureContext loader yet.** Training will currently produce a
  model that learns only on the three base technical features —
  effectively a more-flexible version of the linear weighting, no
  orthogonal information yet. Expected gain in this state is **+1 to
  +3 pp accuracy** (the GBM-vs-linear-weights effect on the same
  features), not the +5 to +10 pp the full Phase 1 + Phase 3 stack
  promises. The big jump waits on the context loaders.
- **`models/` is empty.** `WISECAT_GBM_ENABLED=1` with no artifacts
  causes the scoring path to short-circuit back to legacy via
  `_all_horizons_have_models` — by design. No production behavior change
  until artifacts land.
- **Backend / iOS already deployable.** The new DB columns are
  populated with neutral defaults from the legacy path; the iOS DTO
  decodes the new fields as optional. Shipping the .NET + iOS sides
  before the Python model is fine — no contract is broken.
