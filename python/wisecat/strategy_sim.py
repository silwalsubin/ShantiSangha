"""Rules-based strategy backtest: WiseCat 1M-filter entries, hard stop-loss,
equal-weight sector slots, cash as default.

Answers the v2 question that follows portfolio_sim.py: "if I had run a
disciplined system instead of buying on instinct, what would have happened
to a $40k account through 2008, 2020, 2022?"

Strategy:
  - 10 sector-rep slots, equal-weight (10% of starting capital each).
  - Entry rule: enter long when WiseCat 1M `p_buy > 0.55` for that sector's
    ticker on that day's close.
  - Stop-loss: -8% from entry → exit at next day's open (modeled at the
    close of the trigger day for simplicity). Slot reverts to cash.
  - Re-entry: after a stop, wait for the next p_buy > 0.55 signal. No
    cooldown beyond what the model itself produces.
  - Position cap: 10% per sector, no exceptions. Cap is enforced *by
    construction* — each slot is independent.
  - Cash is a position. Slots that don't pass the filter sit at 0% return.

What this is NOT:
  - Not a walk-forward backtest. The GBM models bundled in `wisecat/models/`
    were trained on data overlapping these regime windows, so any apparent
    "WiseCat edge" is partially in-sample. Treat the *structure* (stop-loss,
    cash fallback, position sizing) as load-bearing, not the model lift.
  - No fees / slippage / dividends / overnight gaps.
  - Daily-close fills only — a -8% stop in a 30%-down day fires at -30%
    here, which is realistic-ish but not perfect.

CLI:
    python -m wisecat.strategy_sim
    python -m wisecat.strategy_sim --regimes worst
    python -m wisecat.strategy_sim --stop-loss 0.10 --entry-threshold 0.60
"""

from __future__ import annotations

import argparse
import sys
import time
from dataclasses import dataclass, field
from datetime import date
from typing import Iterable

import numpy as np
import pandas as pd

from .context_loaders import load_default_context
from .features import FeatureContext
from .portfolio_sim import REGIMES, SECTOR_BASKET, fetch_histories
from .scoring import score_ticker


# -------- Strategy parameters --------------------------------------------------


@dataclass
class StrategyParams:
    starting_capital: float = 40_000.0
    n_slots: int = 10
    stop_loss_pct: float = 0.08          # exit when (close / entry) - 1 < -stop_loss_pct
    entry_threshold: float = 0.55         # WiseCat 1M p_buy must exceed this
    entry_horizon: str = "1M"             # which horizon's p_buy to gate on
    vix_sizing: bool = True               # scale entry size by VIX regime
    vix_low: float = 20.0                 # VIX < vix_low → full position
    vix_high: float = 30.0                # VIX > vix_high → no entry (vix_low ≤ VIX ≤ vix_high → half)
    entry_mode: str = "wisecat"           # "wisecat" (gate on p_buy) or "always" (always-in unless stopped or cooldown)
    cooldown_days: int = 0                # min calendar days after a stop before re-entry. 0 = immediate next signal.
    take_profit_pct: float | None = None  # exit when (close / entry) - 1 >= take_profit_pct. None disables.
    # ---- Active-trader exits (off by default; toggle per-backtest) ------
    trailing_stop_pct: float | None = None  # once a position trades through `trailing_arm_pct`, trail at -trailing_stop_pct from peak. None disables.
    trailing_arm_pct: float = 0.05         # peak-from-entry threshold that arms the trailing stop. Default +5%.
    scale_out_pct: float | None = None     # take partial profit at +scale_out_pct, ride the rest. None disables.
    scale_out_fraction: float = 0.5        # what fraction of the position to take off at scale_out_pct. Default half.
    time_decay_days: int = 0               # 0 disables. If >0 and held this long AND p_buy < time_decay_pbuy_floor at the entry horizon, force-exit.
    time_decay_pbuy_floor: float = 0.50    # p_buy threshold for the time-decay exit. Only consulted when time_decay_days > 0.


# -------- Per-window simulation -----------------------------------------------


@dataclass
class TradeRecord:
    ticker: str
    entry_date: date
    entry_price: float
    deployed: float            # dollars actually put at risk on entry (after VIX sizing)
    slot_balance_at_entry: float  # slot's total balance the moment we entered
    vix_at_entry: float | None = None
    exit_date: date | None = None
    exit_price: float | None = None
    exit_reason: str | None = None  # "stop", "take_profit", "trailing", "scale_out", "time_decay", "window_end"
    # ---- Active-trader exit state ----
    peak_price: float | None = None        # max close seen since entry; drives trailing stop
    scaled_out: bool = False               # set once a scale-out fill has fired

    @property
    def return_pct(self) -> float:
        if self.exit_price is None:
            return float("nan")
        return self.exit_price / self.entry_price - 1.0

    @property
    def dollar_pnl(self) -> float:
        if self.exit_price is None:
            return float("nan")
        return self.deployed * (self.exit_price / self.entry_price - 1.0)


@dataclass
class WindowResult:
    regime: str
    window_start: date
    window_end: date
    n_trading_days: int
    final_equity: float
    total_return: float
    max_drawdown: float
    equity_curve: list[tuple[date, float]] = field(default_factory=list)
    trades: list[TradeRecord] = field(default_factory=list)
    naive_buyhold_return: float | None = None  # equal-weight buy-and-hold over the same window


def _slot_capital(params: StrategyParams) -> float:
    return params.starting_capital / params.n_slots


def _trading_dates_in(history: pd.DataFrame, start: date, end: date) -> list[date]:
    mask = (history["date"] >= start) & (history["date"] <= end)
    return list(history.loc[mask, "date"].tolist())


def _intersect_calendar(histories: dict[str, pd.DataFrame], start: date, end: date) -> list[date]:
    """Union of trading dates across all tickers in [start, end].
    Use union so we don't drop dates where one ticker missed a bar."""
    all_dates: set[date] = set()
    for hist in histories.values():
        all_dates.update(_trading_dates_in(hist, start, end))
    return sorted(all_dates)


def _close_on(history: pd.DataFrame, target: date) -> float | None:
    """Return close on `target` if available; else None. Used for entry/exit fills."""
    row = history.loc[history["date"] == target, "close"]
    if row.empty:
        return None
    val = float(row.iloc[0])
    return val if np.isfinite(val) and val > 0 else None


def _vix_on(vix_history: pd.DataFrame | None, target: date) -> float | None:
    """Latest VIX close on or before `target`. Returns None if no VIX data
    is available (caller should default to full position in that case)."""
    if vix_history is None or vix_history.empty:
        return None
    mask = vix_history["date"] <= target
    if not mask.any():
        return None
    val = vix_history.loc[mask, "close"].iloc[-1]
    if pd.isna(val):
        return None
    return float(val)


def _position_fraction(params: StrategyParams, vix: float | None) -> float:
    """VIX-regime sizing: full / half / cash. If VIX unavailable, treat as
    full position (the strategy still works, just without the gate)."""
    if not params.vix_sizing:
        return 1.0
    if vix is None or not np.isfinite(vix):
        return 1.0
    if vix < params.vix_low:
        return 1.0
    if vix > params.vix_high:
        return 0.0
    return 0.5


_REASON_LABEL = {
    "stop": "STOP  ",
    "trailing": "TRAIL ",
    "take_profit": "TARGET",
    "time_decay": "DECAY ",
    "window_end": "ENDWIN",
}


def _close_trade(
    tr: "TradeRecord",
    d: date,
    close_today: float,
    reason: str,
    slot_balance: dict[str, float],
    ticker: str,
    all_trades: list,
    open_trade: dict,
    verbose: bool,
) -> None:
    """Realize the remaining deployed capital at today's close, mark the
    trade with `reason`, free the slot. Used by every exit path so the
    bookkeeping stays in one place."""
    ret = close_today / tr.entry_price - 1.0
    tr.exit_date = d
    tr.exit_price = close_today
    tr.exit_reason = reason
    slot_balance[ticker] += tr.deployed * ret
    all_trades.append(tr)
    open_trade[ticker] = None
    if verbose:
        label = _REASON_LABEL.get(reason, reason.upper()[:6].ljust(6))
        print(f"    {d}  {label} {ticker:5} entry={tr.entry_price:.2f} "
              f"exit={close_today:.2f}  ret={ret*100:+.1f}%  "
              f"deployed=${tr.deployed:.0f}  slot now ${slot_balance[ticker]:.0f}",
              file=sys.stderr)


def _wisecat_p_buy(
    ticker: str,
    history: pd.DataFrame,
    target: date,
    horizon: str,
    context: FeatureContext,
) -> float | None:
    """Score the ticker as-of `target` using only bars up to and including
    `target`. Returns p_buy for the requested horizon, or None if scoring
    fails (which the caller treats as 'do not enter')."""
    sliced = history.loc[history["date"] <= target]
    if sliced.empty:
        return None
    close = _close_on(sliced, target)
    try:
        score = score_ticker(ticker, sliced, close, context=context)
    except Exception:
        return None
    h = score.horizons.get(horizon)
    if h is None:
        return None
    return float(h.p_buy)


def simulate_window(
    regime: str,
    window: tuple[date, date],
    histories: dict[str, pd.DataFrame],
    context: FeatureContext,
    params: StrategyParams,
    verbose: bool = False,
) -> WindowResult:
    start, end = window
    tickers = list(histories.keys())
    slot_cash = _slot_capital(params)

    calendar = _intersect_calendar(histories, start, end)
    if not calendar:
        return WindowResult(regime, start, end, 0, params.starting_capital, 0.0, 0.0)

    # Per-slot state. Each slot independently holds either cash or one position.
    # `slot_balance` tracks the slot's *total* equity (idle cash + any open
    # position). Updated only when a position closes.
    slot_balance: dict[str, float] = {t: slot_cash for t in tickers}
    open_trade: dict[str, TradeRecord | None] = {t: None for t in tickers}
    last_stop_date: dict[str, date | None] = {t: None for t in tickers}
    all_trades: list[TradeRecord] = []

    equity_curve: list[tuple[date, float]] = []

    vix_history = getattr(context, "vix_history", None)

    for d in calendar:
        # 1. For each open position, evaluate exits in priority order:
        #    hard stop > trailing stop > take-profit > scale-out > time decay.
        #    Hard stop takes precedence on rare days that gap through several
        #    bounds — same daily-close granularity caveat as the rest of this
        #    simulator.
        for ticker in tickers:
            tr = open_trade[ticker]
            if tr is None:
                continue
            close_today = _close_on(histories[ticker], d)
            if close_today is None:
                continue

            # Update the peak first so trailing-stop math sees today's high
            # close. Daily-close granularity — we don't see intraday spikes.
            if tr.peak_price is None or close_today > tr.peak_price:
                tr.peak_price = close_today

            ret = close_today / tr.entry_price - 1.0

            # (a) Hard stop — pre-committed loss limit. Always wins.
            if ret <= -params.stop_loss_pct:
                _close_trade(tr, d, close_today, "stop", slot_balance, ticker, all_trades, open_trade, verbose)
                last_stop_date[ticker] = d
                continue

            # (b) Trailing stop — only fires after the position has armed
            #     (peak ≥ entry * (1 + trailing_arm_pct)). Once armed, exit
            #     when close < peak * (1 - trailing_stop_pct).
            if params.trailing_stop_pct is not None and tr.peak_price is not None:
                armed = tr.peak_price >= tr.entry_price * (1.0 + params.trailing_arm_pct)
                if armed and close_today <= tr.peak_price * (1.0 - params.trailing_stop_pct):
                    _close_trade(tr, d, close_today, "trailing", slot_balance, ticker, all_trades, open_trade, verbose)
                    continue

            # (c) Take-profit at fixed +N%.
            if params.take_profit_pct is not None and ret >= params.take_profit_pct:
                _close_trade(tr, d, close_today, "take_profit", slot_balance, ticker, all_trades, open_trade, verbose)
                continue

            # (d) Scale-out — partial exit at +scale_out_pct. Reduces deployed
            #     capital but leaves the remainder running under stop/trail.
            if (params.scale_out_pct is not None and not tr.scaled_out
                    and ret >= params.scale_out_pct):
                booked_pnl = tr.deployed * ret * params.scale_out_fraction
                slot_balance[ticker] += booked_pnl
                tr.deployed *= (1.0 - params.scale_out_fraction)
                tr.scaled_out = True
                if verbose:
                    print(f"    {d}  SCALE  {ticker:5} entry={tr.entry_price:.2f} "
                          f"close={close_today:.2f}  ret={ret*100:+.1f}%  "
                          f"booked ${booked_pnl:.0f}  remaining deployed ${tr.deployed:.0f}",
                          file=sys.stderr)
                # do NOT continue — let other exits still evaluate this bar.

            # (e) Time decay — if held long enough and the entry-horizon
            #     conviction has rotted, free the slot.
            if params.time_decay_days > 0 and (d - tr.entry_date).days >= params.time_decay_days:
                p_buy_now = _wisecat_p_buy(ticker, histories[ticker], d, params.entry_horizon, context)
                if p_buy_now is not None and p_buy_now < params.time_decay_pbuy_floor:
                    _close_trade(tr, d, close_today, "time_decay", slot_balance, ticker, all_trades, open_trade, verbose)
                    continue

        # 2. For each cash slot, score and enter if filter passes AND
        #    VIX-regime sizing allows a non-zero position.
        vix_today = _vix_on(vix_history, d)
        fraction = _position_fraction(params, vix_today)
        for ticker in tickers:
            if open_trade[ticker] is not None:
                continue
            if fraction <= 0.0:
                continue  # VIX too high — no new entries
            # Cooldown: how many calendar days since the slot last stopped out.
            if params.cooldown_days > 0 and last_stop_date[ticker] is not None:
                if (d - last_stop_date[ticker]).days < params.cooldown_days:
                    continue
            history = histories[ticker]
            close_today = _close_on(history, d)
            if close_today is None:
                continue
            if params.entry_mode == "wisecat":
                p_buy = _wisecat_p_buy(ticker, history, d, params.entry_horizon, context)
                if p_buy is None or p_buy <= params.entry_threshold:
                    continue
            else:
                # "always" mode — always enter when slot is in cash and not in cooldown.
                p_buy = None
            deployed = slot_balance[ticker] * fraction
            tr = TradeRecord(
                ticker=ticker,
                entry_date=d,
                entry_price=close_today,
                deployed=deployed,
                slot_balance_at_entry=slot_balance[ticker],
                vix_at_entry=vix_today,
            )
            open_trade[ticker] = tr
            if verbose:
                sz = "FULL" if fraction == 1.0 else ("HALF" if fraction == 0.5 else f"{fraction*100:.0f}%")
                p_buy_str = f"p_buy={p_buy:.3f}" if p_buy is not None else "always-in"
                vix_str = f"VIX={vix_today:.1f}" if vix_today is not None else "VIX=n/a"
                print(f"    {d}  ENTRY  {ticker:5} price={close_today:.2f}  "
                      f"{p_buy_str}  {vix_str}  size={sz}  "
                      f"deployed=${deployed:.0f}",
                      file=sys.stderr)

        # 3. Mark-to-market portfolio equity at today's close.
        equity = 0.0
        for ticker in tickers:
            tr = open_trade[ticker]
            if tr is None:
                equity += slot_balance[ticker]
            else:
                close_today = _close_on(histories[ticker], d)
                if close_today is None:
                    equity += slot_balance[ticker]
                else:
                    ret = close_today / tr.entry_price - 1.0
                    equity += slot_balance[ticker] + tr.deployed * ret
        equity_curve.append((d, equity))

    # Close any still-open positions at the final available close in the window.
    final_date = calendar[-1]
    for ticker, tr in open_trade.items():
        if tr is None:
            continue
        last_close = _close_on(histories[ticker], final_date)
        if last_close is None:
            window_hist = histories[ticker]
            window_hist = window_hist.loc[(window_hist["date"] >= start) & (window_hist["date"] <= end)]
            if window_hist.empty:
                continue
            last_close = float(window_hist["close"].iloc[-1])
        tr.exit_date = final_date
        tr.exit_price = last_close
        tr.exit_reason = "window_end"
        slot_balance[ticker] += tr.deployed * (last_close / tr.entry_price - 1.0)
        all_trades.append(tr)

    final_equity = sum(slot_balance.values())
    total_return = final_equity / params.starting_capital - 1.0
    max_dd = 0.0
    rolling_peak = params.starting_capital
    for _, eq in equity_curve:
        rolling_peak = max(rolling_peak, eq)
        dd = eq / rolling_peak - 1.0
        max_dd = min(max_dd, dd)

    naive = _naive_buyhold_return(histories, start, end)

    return WindowResult(
        regime=regime,
        window_start=start,
        window_end=end,
        n_trading_days=len(calendar),
        final_equity=final_equity,
        total_return=total_return,
        max_drawdown=max_dd,
        equity_curve=equity_curve,
        trades=all_trades,
        naive_buyhold_return=naive,
    )


def _naive_buyhold_return(histories: dict[str, pd.DataFrame], start: date, end: date) -> float | None:
    """Equal-weight buy-at-window-start, hold-to-window-end return — the
    benchmark the strategy needs to beat."""
    rets: list[float] = []
    for ticker, hist in histories.items():
        in_window = hist.loc[(hist["date"] >= start) & (hist["date"] <= end)]
        if in_window.empty:
            continue
        entry = float(in_window["close"].iloc[0])
        exit_ = float(in_window["close"].iloc[-1])
        if entry > 0 and np.isfinite(entry) and np.isfinite(exit_):
            rets.append(exit_ / entry - 1.0)
    return float(np.mean(rets)) if rets else None


# -------- Reporting -----------------------------------------------------------


def _pct(x: float, sign: bool = True) -> str:
    if x is None or not np.isfinite(x):
        return "  n/a"
    fmt = "+.2f" if sign else ".2f"
    return f"{x*100:{fmt}}%"


def _money(x: float) -> str:
    return f"${x:,.0f}"


def print_window(res: WindowResult) -> None:
    stops = [t for t in res.trades if t.exit_reason == "stop"]
    closed = [t for t in res.trades if t.exit_reason is not None]
    wins = [t for t in closed if (t.return_pct or 0) > 0]
    losses = [t for t in closed if (t.return_pct or 0) <= 0]

    avg_win = float(np.mean([t.return_pct for t in wins])) if wins else float("nan")
    avg_loss = float(np.mean([t.return_pct for t in losses])) if losses else float("nan")
    win_rate = len(wins) / len(closed) if closed else float("nan")

    naive = res.naive_buyhold_return
    delta_vs_naive = (res.total_return - naive) if naive is not None else None

    print(f"  Window: {res.window_start} → {res.window_end}   ({res.n_trading_days} trading days)")
    print(f"    Final equity:       {_money(res.final_equity):>12}   ({_pct(res.total_return):>8})")
    print(f"    Max drawdown:       {_pct(res.max_drawdown):>12}")
    print(f"    Trades closed:      {len(closed)}   ({len(stops)} stops, "
          f"{len(closed) - len(stops)} closed at window-end)")
    print(f"    Win rate:           {win_rate*100:.0f}%   "
          f"(avg win {_pct(avg_win)}, avg loss {_pct(avg_loss)})")
    print(f"    Naive buy-hold:     {_pct(naive) if naive is not None else 'n/a':>12}"
          f"   (Δ vs strategy: {_pct(delta_vs_naive) if delta_vs_naive is not None else 'n/a'})")
    print()


def print_regime_summary(regime: str, results: list[WindowResult]) -> None:
    label_map = {"best": "BEST CASE (bull)", "worst": "WORST CASE (drawdown)",
                 "normal": "NORMAL (sideways/mixed)"}
    print(f"═══ {label_map.get(regime, regime.upper())} ═══")
    print()
    for r in results:
        print_window(r)

    if not results:
        return
    avg_ret = float(np.mean([r.total_return for r in results]))
    avg_dd = float(np.mean([r.max_drawdown for r in results]))
    avg_naive = float(np.mean([r.naive_buyhold_return for r in results if r.naive_buyhold_return is not None]))
    print(f"  Regime average:")
    print(f"    Strategy return:    {_pct(avg_ret):>12}")
    print(f"    Strategy max DD:    {_pct(avg_dd):>12}")
    print(f"    Naive buy-hold:     {_pct(avg_naive):>12}   "
          f"(Δ {_pct(avg_ret - avg_naive)})")
    print()


# -------- Main ----------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Backtest a rules-based strategy (stop-loss + WiseCat filter) "
                    "on the 10-sector basket across historical regimes."
    )
    parser.add_argument("--regimes", default="best,worst,normal",
                        help="Comma-separated regime names.")
    parser.add_argument("--tickers", default=None,
                        help="Comma-separated ticker override. Default = 10-sector basket.")
    parser.add_argument("--capital", type=float, default=40_000.0,
                        help="Starting capital. Default $40,000.")
    parser.add_argument("--stop-loss", type=float, default=0.08,
                        help="Stop-loss fraction. Default 0.08 (-8%%).")
    parser.add_argument("--entry-threshold", type=float, default=0.55,
                        help="Min WiseCat 1M p_buy to enter. Default 0.55.")
    parser.add_argument("--horizon", default="1M",
                        help="WiseCat horizon to gate entries on. Default 1M.")
    parser.add_argument("--entry-mode", choices=("wisecat", "always"), default="wisecat",
                        help="'wisecat' = gate entries on p_buy threshold (default). "
                             "'always' = always-in unless stopped or in cooldown.")
    parser.add_argument("--cooldown-days", type=int, default=0,
                        help="Min calendar days after a stop before re-entry. Default 0.")
    parser.add_argument("--take-profit", type=float, default=None,
                        help="Exit positions when they reach +N from entry "
                             "(e.g. 0.10 = +10%%). Disabled by default.")
    parser.add_argument("--trailing-stop", type=float, default=None,
                        help="Once armed, trail at -N from the peak close "
                             "since entry (e.g. 0.05 = -5%%). Disabled by default.")
    parser.add_argument("--trailing-arm", type=float, default=0.05,
                        help="Peak-from-entry threshold that arms the trailing "
                             "stop. Default 0.05 = +5%%.")
    parser.add_argument("--scale-out", type=float, default=None,
                        help="Take a partial profit at +N (e.g. 0.07 = +7%%). "
                             "Combine with --trailing-stop or --take-profit "
                             "to let the rest run. Disabled by default.")
    parser.add_argument("--scale-out-fraction", type=float, default=0.5,
                        help="Fraction of position to sell at --scale-out. Default 0.5.")
    parser.add_argument("--time-decay-days", type=int, default=0,
                        help="Force-exit positions held this long whose p_buy "
                             "at the entry horizon has dropped below "
                             "--time-decay-floor. 0 disables (default).")
    parser.add_argument("--time-decay-floor", type=float, default=0.50,
                        help="p_buy threshold for the time-decay exit. Default 0.50.")
    parser.add_argument("--no-vix-sizing", action="store_true",
                        help="Disable VIX-regime sizing (always full position).")
    parser.add_argument("--vix-low", type=float, default=20.0,
                        help="VIX below this → full position. Default 20.")
    parser.add_argument("--vix-high", type=float, default=30.0,
                        help="VIX above this → no entries. Default 30. Between low/high = half.")
    parser.add_argument("--workers", type=int, default=8,
                        help="Parallel workers for yfinance fetch. Default 8.")
    parser.add_argument("--verbose", action="store_true",
                        help="Print every entry / stop event.")
    args = parser.parse_args()

    regimes = [r.strip().lower() for r in args.regimes.split(",") if r.strip()]
    for r in regimes:
        if r not in REGIMES:
            raise SystemExit(f"unknown regime: {r}  (choices: {sorted(REGIMES)})")

    if args.tickers:
        tickers = [t.strip().upper() for t in args.tickers.split(",") if t.strip()]
    else:
        tickers = list(SECTOR_BASKET.values())

    params = StrategyParams(
        starting_capital=args.capital,
        n_slots=len(tickers),
        stop_loss_pct=args.stop_loss,
        entry_threshold=args.entry_threshold,
        entry_horizon=args.horizon,
        vix_sizing=not args.no_vix_sizing,
        vix_low=args.vix_low,
        vix_high=args.vix_high,
        entry_mode=args.entry_mode,
        cooldown_days=args.cooldown_days,
        take_profit_pct=args.take_profit,
        trailing_stop_pct=args.trailing_stop,
        trailing_arm_pct=args.trailing_arm,
        scale_out_pct=args.scale_out,
        scale_out_fraction=args.scale_out_fraction,
        time_decay_days=args.time_decay_days,
        time_decay_pbuy_floor=args.time_decay_floor,
    )

    print("=== Strategy Backtest ===", file=sys.stderr)
    print(f"Rules:", file=sys.stderr)
    print(f"  - {len(tickers)} equal-weight sector slots", file=sys.stderr)
    if params.entry_mode == "wisecat":
        print(f"  - Entry: WiseCat {params.entry_horizon} p_buy > {params.entry_threshold}",
              file=sys.stderr)
    else:
        cd = f", {params.cooldown_days}d cooldown after stop" if params.cooldown_days else ""
        print(f"  - Entry: always-in{cd}", file=sys.stderr)
    print(f"  - Stop-loss: -{params.stop_loss_pct*100:.1f}% from entry", file=sys.stderr)
    if params.take_profit_pct is not None:
        print(f"  - Take-profit: +{params.take_profit_pct*100:.1f}% from entry", file=sys.stderr)
    if params.trailing_stop_pct is not None:
        print(f"  - Trailing stop: -{params.trailing_stop_pct*100:.1f}% from peak "
              f"(arms after +{params.trailing_arm_pct*100:.1f}%)", file=sys.stderr)
    if params.scale_out_pct is not None:
        print(f"  - Scale-out: sell {params.scale_out_fraction*100:.0f}% of position at "
              f"+{params.scale_out_pct*100:.1f}%", file=sys.stderr)
    if params.time_decay_days > 0:
        print(f"  - Time decay: exit after {params.time_decay_days}d if "
              f"p_buy < {params.time_decay_pbuy_floor:.2f} at {params.entry_horizon}",
              file=sys.stderr)
    print(f"  - Position cap: {100/len(tickers):.1f}% per slot", file=sys.stderr)
    if params.vix_sizing:
        print(f"  - VIX sizing: full < {params.vix_low:.0f}, half "
              f"{params.vix_low:.0f}–{params.vix_high:.0f}, no entry > {params.vix_high:.0f}",
              file=sys.stderr)
    else:
        print(f"  - VIX sizing: DISABLED (always full position)", file=sys.stderr)
    print(f"  - Starting capital: ${params.starting_capital:,.0f}", file=sys.stderr)
    print(f"Regimes: {', '.join(regimes)}", file=sys.stderr)
    print(f"Tickers: {', '.join(tickers)}", file=sys.stderr)
    print(file=sys.stderr)

    print("Fetching histories…", file=sys.stderr)
    histories = fetch_histories(tickers, workers=args.workers)
    if not histories:
        raise SystemExit("no histories fetched")

    print("Loading WiseCat feature context (SPY + VIX)…", file=sys.stderr)
    context = load_default_context(allow_network=True, tickers_for_earnings=tickers)

    for regime in regimes:
        windows = REGIMES[regime]
        print(f"\nRunning regime: {regime}  ({len(windows)} windows)…", file=sys.stderr)
        results: list[WindowResult] = []
        for win in windows:
            t0 = time.monotonic()
            print(f"  · window {win[0]} → {win[1]}…", file=sys.stderr, flush=True)
            res = simulate_window(regime, win, histories, context, params,
                                  verbose=args.verbose)
            elapsed = time.monotonic() - t0
            print(f"    done in {elapsed:.0f}s  ({res.n_trading_days} bars, "
                  f"{len(res.trades)} trades, final {_money(res.final_equity)})",
                  file=sys.stderr)
            results.append(res)
        print()
        print_regime_summary(regime, results)


if __name__ == "__main__":
    main()
