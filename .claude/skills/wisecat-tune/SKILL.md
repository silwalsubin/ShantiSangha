---
name: wisecat-tune
description: "Tune the per-horizon (1W / 1M / 1Y) technical-strategy weights in the ShantiSangha Stocks (Wise Cat) ensemble. Runs the bundled basket backtest in parallel across the NASDAQ-100 (or a user-supplied ticker list), pools per-strategy hit rates across the basket at each horizon's native forward window (5d / 21d / 252d), and returns a tuning report with mechanical hints. Use this skill whenever the user asks to tune, rebalance, retune, or audit the per-horizon strategy weights, asks 'are the weights still right', wants to see how the ensemble performs across a basket, asks 'which strategies are pulling weight at horizon X', mentions weight tuning for the Stocks feature, asks to validate or sanity-check the weights after adding a new strategy, or types `/wisecat-tune`. Also fire when the user asks to run `tune_basket` directly. Read-only against market data — does not mutate the codebase. After the report runs, propose a revised STRATEGY_WEIGHTS_BY_HORIZON dict based on the diagonal cells; only edit `python/wisecat/strategies/__init__.py` if the user confirms."
---

# Wise Cat — Per-Horizon Weight Tuning

A repeatable, evidence-driven tuning loop for the per-horizon strategy weights in [python/wisecat/strategies/__init__.py](../../../python/wisecat/strategies/__init__.py). Runs the parallel basket backtest, reads off the diagonal cells of the (horizon × forward-window) grid, and proposes a revised weight vector based on basket-pooled hit rates.

## Why this exists

The 1W / 1M / 1Y ensemble has three independent weight vectors. They are first-pass numbers; they need to be re-derived from data whenever:

- A new strategy is added (e.g. when `short_5d_return` or `long_52w_distance` were introduced)
- An existing strategy's behavior is changed (parameter, threshold, normalization)
- Time has passed and the user wants to see whether weights still match the data
- Something feels off in production and the user wants a sanity check

Single-ticker tuning (`python -m wisecat.tune --ticker AAPL …`) is too noisy to set basket-level weights — a momentum-friendly name like AAPL inflates trend signals and crushes oscillators; a beaten-down name does the opposite. **Always tune from a basket.**

The skill bundles the basket tune into one command and gives you (a) micro-averaged hit rates per strategy at each horizon's native forward window, (b) ensemble-level Sharpe / drawdown summaries, (c) mechanical tuning hints, and (d) a recommendation that the agent should compose into a revised `STRATEGY_WEIGHTS_BY_HORIZON` dict.

## How to run it

Default — NASDAQ-100, full history from 2014, 8 parallel workers:

```bash
bash .claude/skills/wisecat-tune/scripts/run.sh
```

Custom tickers / start date / worker count are passed straight through to `wisecat.tune_basket`:

```bash
bash .claude/skills/wisecat-tune/scripts/run.sh --start 2018-01-01
bash .claude/skills/wisecat-tune/scripts/run.sh --tickers AAPL,MSFT,NVDA --start 2018-01-01
bash .claude/skills/wisecat-tune/scripts/run.sh --workers 16
```

The wrapper auto-creates `python/.venv` and installs `wisecat/requirements.txt` on first run; subsequent runs reuse the venv unless requirements have been bumped.

Progress lines (per ticker) stream to stderr as the run proceeds; the final report goes to stdout.

## What the output means

### The diagonal table

For each strategy, three cells are reported — one per horizon — pairing **the current weight** (from `STRATEGY_WEIGHTS_BY_HORIZON`) with the **basket-pooled hit rate** at that horizon's native forward window:

| Horizon | Native forward window | What hit rate measures |
|---------|-----------------------|------------------------|
| 1W      | 5 trading days        | Did the signal's sign predict the 5-day forward return? |
| 1M      | 21 trading days       | Did the signal's sign predict the 21-day forward return? |
| 1Y      | 252 trading days      | Did the signal's sign predict the 252-day forward return? |

The diagonal cells (1W weights × 5d hit rate; 1M × 21d; 1Y × 252d) are the **load-bearing evidence** for the per-horizon weight choices. Off-diagonal cells are not in the basket report — read them per-ticker via `python -m wisecat.tune --ticker X` if you need them.

The `n=` count in each cell is the pooled sample size. Treat anything below n≈500 as noisy and weight it less in the recommendation.

### Tuning hints (mechanical)

Each non-zero weight cell with sufficient sample size emits a hint:

| Hit rate | Hint |
|----------|------|
| < 50%   | ↓ sub coin-flip — consider 0.0 |
| 50–52%  | ↘ marginal — cap ≤ 0.10 |
| 52–55%  | ≈ modest edge |
| ≥ 55%   | ↑ strong edge — consider raising |

Hints are deliberately conservative — they ignore Sharpe, drawdown, signal correlation, and the rest of what actually matters for portfolio construction. They're a starting point for the recommendation, not the final answer.

### Ensemble row

`Ensemble Sharpe (mean / median)`, `Mean total return`, `Mean buy-and-hold`, `Mean max drawdown`, `Mean time long` — these are the per-ticker stats averaged across the basket. Use them as a sanity check that the ensemble is tracking buy-and-hold reasonably (long-only, so you should expect lower returns than B&H but better drawdown / lower variance).

## How to summarize for the user

Read the report and produce:

1. **Headline** — one or two sentences. Which strategies are clearly load-bearing at each horizon, and which are dragging weight without earning it.
2. **Diagonal table** — copy or quote the per-strategy cells. The user wants to see the numbers, not just the conclusion.
3. **Proposed revised weights** — a complete `STRATEGY_WEIGHTS_BY_HORIZON` dict ready to drop into [python/wisecat/strategies/__init__.py](../../../python/wisecat/strategies/__init__.py), with each column summing to 1.0. Reasoning per change.
4. **Confidence / sample-size caveats** — if any cell relies on n < ~500 samples, call it out so the user can decide whether to widen the basket or accept the noise.

When proposing changes:
- Keep the column sums at exactly 1.0 (re-normalize after zeroing or capping a strategy).
- Don't drop a strategy to zero on one horizon if it has 50–52% hit rate — cap at 0.05–0.10 and let the strong horizons carry the load.
- Strategies that consistently pull >55% hit rate across all horizons (e.g. trend, ts_momentum) deserve more weight. Don't let any single one exceed ~0.45 — the point of an ensemble is diversification, not concentration.

## Don't

- **Don't auto-edit `STRATEGY_WEIGHTS_BY_HORIZON`** based on the report. Show the proposed dict, wait for the user to confirm, then edit.
- **Don't tune from a single ticker.** Always run the basket. The single-ticker `wisecat.tune` exists for spot-checking, not for setting weights.
- **Don't use the threshold parameter to chase Sharpe.** Per-strategy hit rate is independent of threshold — only ensemble-level metrics shift. Threshold tuning is a separate question (and `wisecat.backtest --threshold` is the right tool for that).
- **Don't trust hints over context.** A "↓ sub coin-flip" hint on a strategy with 49.7% hit rate at n=100 is noise; the same hint at n=10,000 is real evidence. Read the sample size.
- **Don't update the basket file** (`python/wisecat/data/nasdaq100.txt`) silently. If the user asks to rebalance the basket, propose the change, get confirmation, then edit.
