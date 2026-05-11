"""Daily high-confidence signal scan: scores the 10-sector basket today and
prints tickers where WiseCat's 1M view is strong (Rule 10 of the strategy:
only enter new positions when p_buy ≥ 0.70).

Also flags sells: if `--portfolio` is supplied, any held ticker whose 1M
p_sell ≥ 0.55 is surfaced as a "consider exit" warning. This is *additive*
to the hard -10% stop-loss rule — model-driven exits are advisory, the
price-based stop is non-negotiable.

CLI:
    python -m wisecat.daily_signals
    python -m wisecat.daily_signals --threshold 0.65
    python -m wisecat.daily_signals --portfolio my_portfolio.csv
"""

from __future__ import annotations

import argparse
import sys

from .context_loaders import load_default_context
from .portfolio_sim import SECTOR_BASKET, fetch_histories
from .plan_portfolio import (
    ENTRY_THRESHOLD_P_BUY,
    SELL_SIGNAL_P_SELL,
    parse_portfolio,
    score_basket_for_buys,
    resolve_sector,
)
from .scoring import score_ticker


def _money(x: float) -> str:
    return f"${x:,.2f}"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Scan the 10-sector basket for high-confidence WiseCat signals."
    )
    parser.add_argument("--threshold", type=float, default=ENTRY_THRESHOLD_P_BUY,
                        help=f"Min 1M p_buy to flag as a high-confidence signal. "
                             f"Default {ENTRY_THRESHOLD_P_BUY}.")
    parser.add_argument("--tickers", default=None,
                        help="Comma-separated tickers to scan. Default = 10-sector basket.")
    parser.add_argument("--portfolio", default=None,
                        help="Optional portfolio CSV. If set, also flag sell signals "
                             "(p_sell ≥ 0.55) for owned tickers.")
    parser.add_argument("--workers", type=int, default=8,
                        help="Parallel workers for yfinance fetch. Default 8.")
    args = parser.parse_args()

    if args.tickers:
        scan_tickers = [t.strip().upper() for t in args.tickers.split(",") if t.strip()]
    else:
        scan_tickers = list(SECTOR_BASKET.values())

    # Augment with portfolio tickers for sell-signal checks.
    held_tickers: list[str] = []
    if args.portfolio:
        held_tickers = [p.ticker for p in parse_portfolio(args.portfolio)]
        scan_tickers = sorted(set(scan_tickers + held_tickers))

    print(f"=== Daily WiseCat Signals ===", file=sys.stderr)
    print(f"Scanning {len(scan_tickers)} tickers  (buy threshold p_buy ≥ {args.threshold})",
          file=sys.stderr)
    print(file=sys.stderr)

    histories = fetch_histories(scan_tickers, workers=args.workers)
    if not histories:
        raise SystemExit("no histories fetched")

    print("Loading WiseCat feature context…", file=sys.stderr)
    context = load_default_context(allow_network=True)

    # Score every ticker so we can flag both buys and sells in one pass.
    scored: dict[str, dict] = {}
    for t in sorted(histories.keys()):
        hist = histories[t]
        if hist.empty:
            continue
        price = float(hist["close"].iloc[-1])
        try:
            score = score_ticker(t, hist, price, context=context)
        except Exception as e:
            print(f"  ! scoring failed for {t}: {e}", file=sys.stderr)
            continue
        h1m = score.horizons.get("1M")
        if h1m is None:
            continue
        scored[t] = {
            "p_buy": float(h1m.p_buy),
            "p_sell": float(h1m.p_sell),
            "price": price,
            "sector": resolve_sector(t),
        }

    buys = {t: s for t, s in scored.items() if s["p_buy"] >= args.threshold}
    sells_held = {t: s for t, s in scored.items()
                  if t in held_tickers and s["p_sell"] >= SELL_SIGNAL_P_SELL}
    sells_basket = {t: s for t, s in scored.items()
                    if t not in held_tickers and s["p_sell"] >= SELL_SIGNAL_P_SELL}

    print()
    if buys:
        print(f"▶ HIGH-CONFIDENCE BUYS (p_buy ≥ {args.threshold})")
        for t, s in sorted(buys.items(), key=lambda x: -x[1]["p_buy"]):
            print(f"  {t:<6} {s['sector']:<24} "
                  f"p_buy={s['p_buy']:.2f}  p_sell={s['p_sell']:.2f}  "
                  f"price={_money(s['price'])}")
    else:
        print(f"▶ NO HIGH-CONFIDENCE BUYS today  "
              f"(no ticker exceeded p_buy={args.threshold})")
        # Show the top 3 anyway so user has context.
        top = sorted(scored.values(), key=lambda s: -s["p_buy"])[:3]
        if top:
            print("  Top 3 by p_buy (below threshold but closest):")
            for s in top:
                ticker = next(t for t, v in scored.items() if v is s)
                print(f"    {ticker:<6} {s['sector']:<24} p_buy={s['p_buy']:.2f}  "
                      f"price={_money(s['price'])}")
    print()

    if held_tickers:
        if sells_held:
            print(f"▶ EXIT WARNINGS — held tickers with p_sell ≥ {SELL_SIGNAL_P_SELL}")
            for t, s in sorted(sells_held.items(), key=lambda x: -x[1]["p_sell"]):
                print(f"  {t:<6} {s['sector']:<24} "
                      f"p_sell={s['p_sell']:.2f}  p_buy={s['p_buy']:.2f}  "
                      f"price={_money(s['price'])}")
            print(f"  → Consider closing these on your next trading day. "
                  f"(Hard -10% stop still applies regardless.)")
        else:
            print("▶ No exit warnings on currently-held tickers.")
        print()

    if sells_basket:
        print(f"▶ BASKET TICKERS UNDER PRESSURE (informational only — not held)")
        for t, s in sorted(sells_basket.items(), key=lambda x: -x[1]["p_sell"]):
            print(f"  {t:<6} {s['sector']:<24} p_sell={s['p_sell']:.2f}")
        print()


if __name__ == "__main__":
    main()
