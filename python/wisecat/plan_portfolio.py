"""Portfolio plan generator: take the user's CURRENT holdings, score them
against the 10 ratified rules, and emit a concrete action plan.

INPUT — a CSV with columns: `ticker, shares, cost_basis` (cost basis per
share, not total). Optional `--cash` for un-invested balance. Example:

    ticker,shares,cost_basis
    NVDA,50,400.00
    TSLA,30,180.00
    AAPL,40,150.00
    SPY,20,400.00

OUTPUT — a written plan, in this order:
  1. Portfolio snapshot (value, sector spread, cash)
  2. Rule violations (concentration, stop-loss already triggered)
  3. WiseCat read on each holding (p_buy / p_sell at 1M)
  4. Recommended actions: EXITS, TRIMS, ADDS, HOLDS
  5. Stop-loss levels for everything you keep

Strict policy: this tool does not execute trades. It generates the plan
you execute manually on your monthly trading day.

CLI:
    python -m wisecat.plan_portfolio --input my_portfolio.csv
    python -m wisecat.plan_portfolio --input portfolio.csv --cash 5000
"""

from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from typing import Iterable

import numpy as np
import pandas as pd

from .context_loaders import load_default_context
from .features import FeatureContext
from .portfolio_sim import SECTOR_BASKET, fetch_histories
from .scoring import score_ticker


# Hardcoded sector overrides for common large-cap names. yfinance .info is
# unreliable enough that we want a fast path for stocks the user is likely
# to hold. Anything not in this map falls back to yfinance.
SECTOR_OVERRIDES: dict[str, str] = {
    # Information Technology
    "AAPL": "Information Technology", "MSFT": "Information Technology",
    "NVDA": "Information Technology", "AMD": "Information Technology",
    "INTC": "Information Technology", "AVGO": "Information Technology",
    "CRM": "Information Technology", "ORCL": "Information Technology",
    "ADBE": "Information Technology", "CSCO": "Information Technology",
    "ACN": "Information Technology", "IBM": "Information Technology",
    "QCOM": "Information Technology", "TXN": "Information Technology",
    "NOW": "Information Technology", "PANW": "Information Technology",
    "PLTR": "Information Technology", "SMCI": "Information Technology",
    # Health Care
    "JNJ": "Health Care", "UNH": "Health Care", "PFE": "Health Care",
    "LLY": "Health Care", "ABBV": "Health Care", "MRK": "Health Care",
    "TMO": "Health Care", "ABT": "Health Care", "DHR": "Health Care",
    "BMY": "Health Care", "AMGN": "Health Care", "CVS": "Health Care",
    "ISRG": "Health Care",
    # Financials
    "JPM": "Financials", "BAC": "Financials", "WFC": "Financials",
    "GS": "Financials", "MS": "Financials", "C": "Financials",
    "BLK": "Financials", "BRK-A": "Financials", "BRK-B": "Financials",
    "BRK.A": "Financials", "BRK.B": "Financials", "V": "Financials",
    "MA": "Financials", "AXP": "Financials", "SCHW": "Financials",
    "COF": "Financials", "USB": "Financials",
    # Consumer Discretionary
    "HD": "Consumer Discretionary", "AMZN": "Consumer Discretionary",
    "TSLA": "Consumer Discretionary", "NKE": "Consumer Discretionary",
    "MCD": "Consumer Discretionary", "SBUX": "Consumer Discretionary",
    "LOW": "Consumer Discretionary", "BKNG": "Consumer Discretionary",
    "ORLY": "Consumer Discretionary", "TJX": "Consumer Discretionary",
    "F": "Consumer Discretionary", "GM": "Consumer Discretionary",
    # Consumer Staples
    "PG": "Consumer Staples", "KO": "Consumer Staples", "PEP": "Consumer Staples",
    "WMT": "Consumer Staples", "COST": "Consumer Staples", "MO": "Consumer Staples",
    "PM": "Consumer Staples", "CL": "Consumer Staples", "MDLZ": "Consumer Staples",
    "TGT": "Consumer Staples",
    # Communication Services
    "VZ": "Communication Services", "T": "Communication Services",
    "GOOGL": "Communication Services", "GOOG": "Communication Services",
    "META": "Communication Services", "DIS": "Communication Services",
    "NFLX": "Communication Services", "CMCSA": "Communication Services",
    "TMUS": "Communication Services",
    # Industrials
    "CAT": "Industrials", "BA": "Industrials", "GE": "Industrials",
    "HON": "Industrials", "UPS": "Industrials", "RTX": "Industrials",
    "LMT": "Industrials", "MMM": "Industrials", "DE": "Industrials",
    "UNP": "Industrials", "FDX": "Industrials", "NOC": "Industrials",
    # Energy
    "XOM": "Energy", "CVX": "Energy", "COP": "Energy", "EOG": "Energy",
    "SLB": "Energy", "OXY": "Energy", "MPC": "Energy", "PSX": "Energy",
    # Utilities
    "NEE": "Utilities", "DUK": "Utilities", "SO": "Utilities",
    "AEP": "Utilities", "D": "Utilities", "EXC": "Utilities",
    # Materials
    "APD": "Materials", "LIN": "Materials", "SHW": "Materials",
    "ECL": "Materials", "NEM": "Materials", "FCX": "Materials",
    "DD": "Materials",
    # Real Estate
    "PLD": "Real Estate", "AMT": "Real Estate", "EQIX": "Real Estate",
    "CCI": "Real Estate", "O": "Real Estate", "SPG": "Real Estate",
    # Common ETFs — broad-market, not single sector
    "SPY": "ETF (Broad)", "VOO": "ETF (Broad)", "VTI": "ETF (Broad)",
    "QQQ": "ETF (Tech-heavy)", "IWM": "ETF (Small-cap)",
}


# Rule thresholds — match project_trading_strategy_rules.md.
POSITION_CAP_PCT = 0.10              # Rule 2: 10% max per position
STOP_LOSS_PCT = 0.10                 # Rule 3: -10% hard stop
ENTRY_THRESHOLD_P_BUY = 0.70         # Rule 10: only enter on p_buy > 0.70
SELL_SIGNAL_P_SELL = 0.55            # Internal: WiseCat strongly suggests exit
MIN_SECTORS = 8                      # Rule 1: ≥ 8 sectors at all times


@dataclass
class Position:
    ticker: str
    shares: float
    cost_basis: float       # per share
    current_price: float | None = None
    sector: str | None = None
    p_buy_1m: float | None = None
    p_sell_1m: float | None = None

    @property
    def market_value(self) -> float:
        if self.current_price is None:
            return 0.0
        return self.shares * self.current_price

    @property
    def cost_total(self) -> float:
        return self.shares * self.cost_basis

    @property
    def unrealized_pnl(self) -> float:
        return self.market_value - self.cost_total

    @property
    def unrealized_pct(self) -> float | None:
        if self.cost_basis <= 0 or self.current_price is None:
            return None
        return self.current_price / self.cost_basis - 1.0


def parse_portfolio(path: str) -> list[Position]:
    positions: list[Position] = []
    with open(path, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ticker = row.get("ticker", "").strip().upper()
            if not ticker:
                continue
            try:
                shares = float(row.get("shares", "0"))
                cost_basis = float(row.get("cost_basis", "0"))
            except ValueError:
                print(f"  ! skipping {ticker}: bad number in row {row}", file=sys.stderr)
                continue
            if shares <= 0 or cost_basis <= 0:
                continue
            positions.append(Position(ticker=ticker, shares=shares, cost_basis=cost_basis))
    return positions


def resolve_sector(ticker: str) -> str:
    if ticker in SECTOR_OVERRIDES:
        return SECTOR_OVERRIDES[ticker]
    try:
        import yfinance as yf
        info = yf.Ticker(ticker).info
        sector = info.get("sector")
        if sector:
            return sector
    except Exception:
        pass
    return "Unknown"


def annotate_positions(
    positions: list[Position],
    histories: dict[str, pd.DataFrame],
    context: FeatureContext,
) -> None:
    """Fill in current_price, sector, and WiseCat 1M probabilities for each
    position. Mutates in place."""
    for p in positions:
        p.sector = resolve_sector(p.ticker)
        hist = histories.get(p.ticker)
        if hist is None or hist.empty:
            continue
        last_row = hist.iloc[-1]
        p.current_price = float(last_row["close"])
        try:
            score = score_ticker(p.ticker, hist, p.current_price, context=context)
            h1m = score.horizons.get("1M")
            if h1m is not None:
                p.p_buy_1m = float(h1m.p_buy)
                p.p_sell_1m = float(h1m.p_sell)
        except Exception as e:
            print(f"  ! scoring failed for {p.ticker}: {e}", file=sys.stderr)


def score_basket_for_buys(
    tickers: Iterable[str],
    histories: dict[str, pd.DataFrame],
    context: FeatureContext,
    threshold: float = ENTRY_THRESHOLD_P_BUY,
) -> dict[str, dict]:
    """Return {ticker: {p_buy, p_sell, price, sector}} for any basket
    ticker whose 1M p_buy currently exceeds `threshold`."""
    out: dict[str, dict] = {}
    for t in tickers:
        hist = histories.get(t)
        if hist is None or hist.empty:
            continue
        price = float(hist["close"].iloc[-1])
        try:
            score = score_ticker(t, hist, price, context=context)
        except Exception:
            continue
        h1m = score.horizons.get("1M")
        if h1m is None:
            continue
        if h1m.p_buy >= threshold:
            out[t] = {
                "p_buy": float(h1m.p_buy),
                "p_sell": float(h1m.p_sell),
                "price": price,
                "sector": resolve_sector(t),
            }
    return out


# -------- Reporting -----------------------------------------------------------


def _money(x: float) -> str:
    return f"${x:,.0f}"


def _pct(x: float | None, sign: bool = True) -> str:
    if x is None or not np.isfinite(x):
        return "  n/a"
    fmt = "+.1f" if sign else ".1f"
    return f"{x*100:{fmt}}%"


def print_plan(positions: list[Position], cash: float,
               basket_buy_signals: dict[str, dict]) -> None:
    total_value = sum(p.market_value for p in positions) + cash
    invested = total_value - cash

    print()
    print("══════════════════════════════════════════════════════════════")
    print("  PORTFOLIO AUDIT & PLAN")
    print("══════════════════════════════════════════════════════════════")
    print()
    print(f"Total value:    {_money(total_value)}")
    print(f"  Invested:     {_money(invested)}  ({invested/total_value*100:.0f}%)")
    print(f"  Cash:         {_money(cash)}  ({cash/total_value*100:.0f}%)")
    print(f"Positions:      {len(positions)}")
    print()

    # ------- Holdings table ---------------------------------------------------
    print("── Current holdings ──────────────────────────────────────────")
    print(f"  {'ticker':<7} {'sector':<25} {'shares':>9} {'price':>9} "
          f"{'mkt val':>10} {'%port':>7} {'P&L%':>8} {'p_buy':>6} {'p_sell':>7}")
    for p in sorted(positions, key=lambda x: -x.market_value):
        pct_port = p.market_value / total_value if total_value else 0.0
        print(f"  {p.ticker:<7} {(p.sector or '?'):<25} "
              f"{p.shares:>9.1f} {p.current_price or 0:>9.2f} "
              f"{_money(p.market_value):>10} "
              f"{pct_port*100:>6.1f}% "
              f"{_pct(p.unrealized_pct):>8} "
              f"{(p.p_buy_1m if p.p_buy_1m is not None else 0):>6.2f} "
              f"{(p.p_sell_1m if p.p_sell_1m is not None else 0):>7.2f}")
    print()

    # ------- Sector spread ----------------------------------------------------
    sector_totals: dict[str, float] = {}
    for p in positions:
        s = p.sector or "Unknown"
        sector_totals[s] = sector_totals.get(s, 0.0) + p.market_value
    covered_sectors = {s for s in sector_totals if s in SECTOR_BASKET}
    missing_sectors = [s for s in SECTOR_BASKET if s not in covered_sectors]

    print("── Sector spread (Rule 1: 8+ sectors required) ──────────────")
    for s, v in sorted(sector_totals.items(), key=lambda x: -x[1]):
        flag = "  ← over-cap" if v / total_value > POSITION_CAP_PCT * 2 else ""
        print(f"  {s:<26} {_money(v):>10}  ({v/total_value*100:>5.1f}%){flag}")
    n_basket_sectors = len(covered_sectors)
    print()
    print(f"  Basket sectors covered: {n_basket_sectors}/10  "
          f"{'✓' if n_basket_sectors >= MIN_SECTORS else '✗ BELOW MIN (8 required)'}")
    if missing_sectors:
        print(f"  Missing: {', '.join(missing_sectors)}")
    print()

    # ------- Rule-violation triage --------------------------------------------
    exits: list[tuple[Position, str]] = []
    trims: list[tuple[Position, str, float]] = []  # (pos, reason, shares_to_sell)
    holds: list[Position] = []

    for p in positions:
        pct_port = p.market_value / total_value if total_value else 0.0
        reasons: list[str] = []

        # Rule 3: already past stop-loss
        if p.unrealized_pct is not None and p.unrealized_pct <= -STOP_LOSS_PCT:
            reasons.append(f"Rule 3 violated: down {p.unrealized_pct*100:+.1f}% "
                           f"(below -{STOP_LOSS_PCT*100:.0f}% stop)")

        # Strong sell signal from WiseCat
        if p.p_sell_1m is not None and p.p_sell_1m >= SELL_SIGNAL_P_SELL:
            reasons.append(f"WiseCat 1M p_sell={p.p_sell_1m:.2f} ≥ {SELL_SIGNAL_P_SELL:.2f}")

        if reasons:
            exits.append((p, "; ".join(reasons)))
            continue

        # Rule 2: concentration cap
        if pct_port > POSITION_CAP_PCT * 1.05:  # 5% tolerance before flagging trim
            target_value = POSITION_CAP_PCT * total_value
            excess_value = p.market_value - target_value
            shares_to_sell = excess_value / (p.current_price or 1.0)
            trims.append((p, f"Rule 2: {pct_port*100:.1f}% of portfolio "
                             f"(cap is {POSITION_CAP_PCT*100:.0f}%)",
                          shares_to_sell))
            continue

        holds.append(p)

    print("── Recommended actions ──────────────────────────────────────")
    print()

    if exits:
        print("  ▶ IMMEDIATE EXITS (rule violations):")
        for p, reason in exits:
            print(f"    SELL {p.shares:.1f} {p.ticker:<6} @ ~{_money(p.current_price or 0)}/sh = "
                  f"{_money(p.market_value)}")
            print(f"         reason: {reason}")
        proceeds = sum(p.market_value for p, _ in exits)
        print(f"    → cash recovered: {_money(proceeds)}")
        print()

    if trims:
        print("  ▶ TRIM TO 10% CAP (Rule 2):")
        for p, reason, shares_to_sell in trims:
            print(f"    SELL {shares_to_sell:.1f} {p.ticker:<6} @ ~{_money(p.current_price or 0)}/sh "
                  f"= {_money(shares_to_sell * (p.current_price or 0))}")
            print(f"         leaves: {p.shares - shares_to_sell:.1f} sh "
                  f"({POSITION_CAP_PCT*100:.0f}% of portfolio)")
        print()

    # New buys: sectors missing + currently-high-confidence WiseCat signals
    available_cash_estimate = cash + sum(p.market_value for p, _ in exits) + sum(
        s * (p.current_price or 0) for p, _, s in trims
    )
    sectors_after_exit = {p.sector for p in holds + [p for p, _, _ in trims]
                          if p.sector in SECTOR_BASKET}
    sectors_still_missing = [s for s in SECTOR_BASKET if s not in sectors_after_exit]
    target_per_slot = total_value * POSITION_CAP_PCT

    if sectors_still_missing or basket_buy_signals:
        print("  ▶ ADD POSITIONS (Rule 1 + Rule 10):")
        print(f"    Available cash after exits/trims: ~{_money(available_cash_estimate)}")
        print(f"    Target per new slot (~10% of portfolio): {_money(target_per_slot)}")
        print()

        # Missing sectors first
        for sector in sectors_still_missing:
            default_ticker = SECTOR_BASKET[sector]
            signal = basket_buy_signals.get(default_ticker)
            if signal:
                conf = f"p_buy={signal['p_buy']:.2f} ✓ HIGH CONFIDENCE"
            else:
                conf = "no current high-conf signal — defer or use limit order"
            price = signal["price"] if signal else None
            shares_to_buy = (target_per_slot / price) if price else 0
            price_str = f"~{_money(price)}/sh" if price else "fetch current price"
            print(f"    BUY  {sector}: {default_ticker}  ({conf})")
            if shares_to_buy > 0:
                print(f"         ~{shares_to_buy:.1f} sh @ {price_str} = {_money(target_per_slot)}")
            print()

        # Extra high-conf signals in sectors already held (only if cash permits)
        extras = [
            (t, sig) for t, sig in basket_buy_signals.items()
            if sig["sector"] not in sectors_still_missing
        ]
        if extras and available_cash_estimate > target_per_slot:
            print(f"    Additional high-confidence signals "
                  f"(already covered, optional add):")
            for t, sig in extras:
                print(f"      {t:<6} {sig['sector']:<24} p_buy={sig['p_buy']:.2f}  "
                      f"price={_money(sig['price'])}")
            print()

    if holds:
        print("  ▶ HOLD (in good shape):")
        for p in holds:
            stop_price = (p.current_price or 0) * (1.0 - STOP_LOSS_PCT)
            print(f"    {p.ticker:<6} {_money(p.market_value):>9}  "
                  f"stop @ {_money(stop_price)} (-{STOP_LOSS_PCT*100:.0f}% from current)")
        print()

    # ------- Final picture ----------------------------------------------------
    final_n_sectors = len(sectors_after_exit | set(sectors_still_missing))
    print("── Post-plan portfolio structure ────────────────────────────")
    print(f"  Sectors covered (if all adds executed): "
          f"{final_n_sectors}/10  "
          f"{'✓' if final_n_sectors >= MIN_SECTORS else '✗'}")
    print(f"  Max position size: {POSITION_CAP_PCT*100:.0f}%")
    print(f"  Stop-loss on every position: -{STOP_LOSS_PCT*100:.0f}%")
    print(f"  New entries require WiseCat 1M p_buy > {ENTRY_THRESHOLD_P_BUY}")
    print()
    print("Reminder: execute these on your monthly trading day. "
          "Stops fire ad-hoc if breached.")
    print()


# -------- Main ----------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate an action plan for the user's current stock "
                    "portfolio against the 10 ratified rules."
    )
    parser.add_argument("--input", required=True,
                        help="CSV with columns: ticker, shares, cost_basis.")
    parser.add_argument("--cash", type=float, default=0.0,
                        help="Un-invested cash balance to include in portfolio total.")
    parser.add_argument("--workers", type=int, default=8,
                        help="Parallel workers for yfinance fetch. Default 8.")
    args = parser.parse_args()

    positions = parse_portfolio(args.input)
    if not positions:
        raise SystemExit(f"no valid positions parsed from {args.input}")

    print(f"Parsed {len(positions)} positions from {args.input}", file=sys.stderr)

    # Fetch histories for held tickers + the full 10-sector basket (we need
    # to score the basket for missing-sector recommendations).
    all_tickers = sorted(set([p.ticker for p in positions]) | set(SECTOR_BASKET.values()))
    print(f"Fetching histories for {len(all_tickers)} tickers…", file=sys.stderr)
    histories = fetch_histories(all_tickers, workers=args.workers)
    if not histories:
        raise SystemExit("no histories fetched")

    print("Loading WiseCat feature context (SPY + VIX)…", file=sys.stderr)
    context = load_default_context(allow_network=True)

    print("Scoring current holdings…", file=sys.stderr)
    annotate_positions(positions, histories, context)

    print(f"Scanning the basket for high-confidence buy signals "
          f"(p_buy ≥ {ENTRY_THRESHOLD_P_BUY})…", file=sys.stderr)
    buy_signals = score_basket_for_buys(
        SECTOR_BASKET.values(), histories, context, threshold=ENTRY_THRESHOLD_P_BUY,
    )
    if buy_signals:
        print(f"  found {len(buy_signals)} high-confidence basket signals", file=sys.stderr)
    else:
        print(f"  no basket ticker currently exceeds {ENTRY_THRESHOLD_P_BUY}", file=sys.stderr)

    print_plan(positions, args.cash, buy_signals)


if __name__ == "__main__":
    main()
