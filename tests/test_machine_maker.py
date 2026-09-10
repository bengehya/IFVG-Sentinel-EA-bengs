#!/usr/bin/env python3
"""MACHINE MAKER regression matrix A–K."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from machine_maker import (
    BIAS_BEAR,
    BIAS_BULL,
    BIAS_NEUTRAL,
    DIR_BUY,
    DIR_SELL,
    HARD_MAX_LOT,
    HARD_TARGET_RR,
    MODEL_MID,
    MODEL_NONE,
    MODEL_WICK,
    SL_FIB62_LARGE,
    SL_FIB62_SMALL,
    SL_FVG,
    ST_WAITING_RETEST,
    TF_DAILY,
    TF_H4,
    TF_M15,
    CapitalGuard,
    align_bias,
    bias_from_swings,
    build_fib,
    capital_target_reached,
    choose_sl,
    completely_broken,
    cooldown_end,
    detect_entry,
    fvg_on_correct_side,
    is_cooldown_active,
    is_gold_symbol,
    lock_strategy_timeframes,
    lot_from_allowed_risk,
    model1,
    model2,
    process_wait_ticks,
    reward_meets_target,
    risk_money,
    three_candle_bearish,
    three_candle_bullish,
    tp_from_rr,
)


def run() -> int:
    failed = 0
    passed = 0

    def check(name: str, cond: bool, detail: str = "") -> None:
        nonlocal failed, passed
        if cond:
            print(f"PASS  {name}" + (f" — {detail}" if detail else ""))
            passed += 1
        else:
            print(f"FAIL  {name}" + (f" — {detail}" if detail else ""))
            failed += 1

    # A. Direction
    check("A D1+H4 bullish", align_bias(bias_from_swings(2, 1, 2, 1), bias_from_swings(4, 3, 4, 3)) == BIAS_BULL)
    check("A D1+H4 bearish", align_bias(bias_from_swings(1, 2, 1, 2), bias_from_swings(3, 4, 3, 4)) == BIAS_BEAR)
    check("A disagreement", align_bias(BIAS_BULL, BIAS_BEAR) == BIAS_NEUTRAL)
    check("A mixed swings = neutral", bias_from_swings(2, 1, 1, 2) == BIAS_NEUTRAL)
    check("A gold-only XAUUSD", is_gold_symbol("XAUUSD"))
    check("A gold-only rejects EURUSD", not is_gold_symbol("EURUSD"))

    # B. Fibonacci
    fb = build_fib(DIR_BUY, 2000.0, 1000.0)
    check("B bull 50% midpoint", abs(fb["fib_50"] - 1500.0) < 1e-9)
    check("B bull 62% retrace from high", abs(fb["fib_62"] - 1380.0) < 1e-9)
    fe = build_fib(DIR_SELL, 2000.0, 1000.0)
    check("B bear 50% midpoint", abs(fe["fib_50"] - 1500.0) < 1e-9)
    check("B bear 62% retrace from low", abs(fe["fib_62"] - 1620.0) < 1e-9)
    check("B bull 0.00 is swing high", abs(fb["fib_00"] - 2000.0) < 1e-9)
    check("B bear 0.00 is swing low", abs(fe["fib_00"] - 1000.0) < 1e-9)

    # C. FVG
    bull = three_candle_bullish(100.0, 101.0, 0.5)
    check("C bullish FVG gap", bull == (101.0, 100.0))
    check("C no bullish FVG if overlapping", three_candle_bullish(100.0, 99.0, 0.1) is None)
    bear = three_candle_bearish(100.0, 99.0, 0.5)
    check("C bearish FVG gap", bear == (100.0, 99.0))
    check("C discount FVG below 50%", fvg_on_correct_side(DIR_BUY, fb, 1400.0, 1300.0))
    check("C FVG in premium rejected for bull", not fvg_on_correct_side(DIR_BUY, fb, 1800.0, 1700.0))
    check("C premium FVG above 50%", fvg_on_correct_side(DIR_SELL, fe, 1800.0, 1700.0))
    check("C full break bull close below low", completely_broken(DIR_BUY, 101.0, 100.0, 99.9))
    check("C close inside is not a full break", not completely_broken(DIR_BUY, 101.0, 100.0, 100.5))

    # D. Entry model 1
    fvg_h, fvg_l = 101.0, 100.0
    m1_ok, wick, close_out = model1(DIR_BUY, {"high": 101.5, "low": 100.4, "close": 101.2}, fvg_h, fvg_l)
    check("D model1 wick+close outside BUY", m1_ok and wick and close_out)
    check("D model1 close inside rejected", not model1(DIR_BUY, {"high": 101.2, "low": 100.4, "close": 100.6}, fvg_h, fvg_l)[0])
    check("D model1 close above without wick rejected", not model1(DIR_BUY, {"high": 103.0, "low": 102.0, "close": 102.5}, fvg_h, fvg_l)[0])
    check("D model1 no wick (fully above)", not model1(DIR_BUY, {"high": 103.0, "low": 102.0, "close": 102.5}, fvg_h, fvg_l)[0])
    check("D detect prefers model1", detect_entry(DIR_BUY, {"high": 101.5, "low": 100.4, "close": 101.2}, fvg_h, fvg_l) == MODEL_WICK)
    m1s, _, _ = model1(DIR_SELL, {"high": 100.6, "low": 99.5, "close": 99.8}, 101.0, 100.0)
    check("D model1 SELL mirror", m1s)

    # E. Entry model 2
    mid_ok, touch, close50 = model2(DIR_BUY, {"high": 101.0, "low": 100.4, "close": 100.7}, fvg_h, fvg_l)
    check("E model2 50% touch + close above", mid_ok and touch and close50)
    check("E model2 close below 50% rejected", not model2(DIR_BUY, {"high": 100.6, "low": 100.3, "close": 100.4}, fvg_h, fvg_l)[0])
    check("E full break not an entry", detect_entry(DIR_BUY, {"high": 101.0, "low": 99.0, "close": 99.5}, fvg_h, fvg_l) == MODEL_NONE)
    check("E no third model", detect_entry(DIR_BUY, {"high": 103, "low": 102, "close": 102.5}, fvg_h, fvg_l) == MODEL_NONE)

    # F. SL
    # Gold-like ticks
    ts, tv = 0.01, 1.0
    entry = 1400.0
    raw = 1370.0  # farther than 0.62, 0.01 lot = $30 < $50 allowed
    fib62 = 1380.0
    sl_n, why_n = choose_sl(DIR_BUY, entry, raw, fib62, 0.0, ts, tv, 50.0)
    check("F normal FVG SL when 0.01 fits", why_n == SL_FVG and abs(sl_n - raw) < 1e-12)
    raw_big = 1200.0  # 200 distance, 0.01 lot = $200 > $10, 0.62 closer
    sl_l, why_l = choose_sl(DIR_BUY, entry, raw_big, fib62, 0.0, ts, tv, 10.0)
    check("F large FVG uses 0.62", why_l == SL_FIB62_LARGE and abs(sl_l - fib62) < 1e-12)
    raw_small = 1395.0  # tighter than 1380
    sl_s, why_s = choose_sl(DIR_BUY, entry, raw_small, fib62, 0.0, ts, tv, 10.0)
    check("F small FVG uses 0.62 farther", why_s == SL_FIB62_SMALL and abs(sl_s - fib62) < 1e-12)

    # G. RR 1:4
    tp = tp_from_rr(DIR_BUY, 100.0, 90.0, 4.0)
    ok4, rr4 = reward_meets_target(100.0, 90.0, tp, 4.0)
    check("G TP is exactly 1:4", ok4 and abs(rr4 - 4.0) < 1e-9 and abs(tp - 140.0) < 1e-9)
    ok3, rr3 = reward_meets_target(100.0, 90.0, 130.0, 4.0)
    check("G 1:3 is rejected", (not ok3) and abs(rr3 - 3.0) < 1e-9)
    check("G hardcoded target is 4 not 3", abs(HARD_TARGET_RR - 4.0) < 1e-12)

    # H. Risk
    for bal, money in ((50.0, 10.0), (100.0, 10.0), (200.0, 10.0)):
        theo, lot, actual, rej = lot_from_allowed_risk(ts, tv, 5.0, money)
        check(f"H ${bal:.0f} max ${money:.0f} lot<=0.01", lot <= HARD_MAX_LOT + 1e-12 and rej == "")
    _, lot_cap, _, _ = lot_from_allowed_risk(ts, tv, 1.0, 1000.0)
    check("H lot never > 0.01", lot_cap <= HARD_MAX_LOT + 1e-12)
    theo5, lot5, _, rej5 = lot_from_allowed_risk(ts, tv, 15.41, 10.0)
    check("H wide SL min-lot may NO TRADE", lot5 == 0.0 and "minimum lot exceeds" in rej5, f"theo={theo5:.4f}")

    # I. Cooldown
    c = 2
    start = 1_704_067_200
    end = cooldown_end(start, 8)
    check("I 2 SL → 8h", end - start == 8 * 3600)
    check("I blocked during 8h", is_cooldown_active(end - 1, end))
    check("I resume at 8h", not is_cooldown_active(end, end))
    check("I third trade blocked while active", is_cooldown_active(start + 60, end))

    # J. Capital protection
    store = {}
    g = CapitalGuard(store)
    g.init(50.0, 50.0, 50.0, reset=False)
    check("J start $50 target $250", abs(g.target - 250.0) < 1e-9 and g.can_trade())
    g.evaluate(250.0, 250.0)
    check("J $50→$250 locks", g.locked and not g.can_trade())
    check("J persist lock flag", store["locked"] is True)
    g2 = CapitalGuard(store)
    g2.init(50.0, 40.0, 40.0, reset=False)  # restart after DD, still locked
    check("J restart while locked stays locked", g2.locked and not g2.can_trade())
    check("J balance drop does not auto-unlock", not capital_target_reached(g2.start, 5.0, 40.0, 40.0) and g2.locked)
    g2.init(50.0, 80.0, 80.0, reset=True)
    check("J manual reset reopens", (not g2.locked) and abs(g2.start - 80.0) < 1e-9 and abs(g2.target - 400.0) < 1e-9)

    # K. Timeframe independence
    for chart in ("PERIOD_M1", "PERIOD_M5", "PERIOD_M15", "PERIOD_H1"):
        locked = lock_strategy_timeframes(chart)
        check(
            f"K tester {chart} still D1/H4/M15",
            locked == {"daily": TF_DAILY, "h4": TF_H4, "m15": TF_M15},
        )

    wait = {"state": ST_WAITING_RETEST, "m15_checks": 0, "entry_logs": []}
    process_wait_ticks(wait, 60, new_m15_every=0)
    check("K/wait no per-tick M15 revalidation", wait["m15_checks"] == 0)

    print(f"\npassed={passed} failed={failed}")
    return failed


if __name__ == "__main__":
    raise SystemExit(run())
