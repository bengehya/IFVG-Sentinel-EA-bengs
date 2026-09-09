#!/usr/bin/env python3
"""Timeframe lock + monetary risk engine (strategy rules unchanged)."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from ifvg_safety import (
    EXECUTION_TIMEFRAME,
    HARD_MAX_LOT,
    HTF_TIMEFRAME,
    LOG_ENTRY_VALIDATION,
    SETUP_TIMEFRAME,
    ST_IDLE,
    ST_WAITING_RETEST,
    TESTER_WAIT_TICKS,
    allowed_risk_money,
    clamp_lot_hard_cap,
    cooldown_end_from_start,
    create_ifvg_setup,
    default_cfg,
    is_cooldown_active,
    lock_strategy_timeframes,
    lot_from_allowed_risk,
    margin_is_sufficient,
    perfect_buy_setup,
    process_ifvg_tick,
    realized_r,
    replay_expired_ifvg_ticks,
    replay_zone_wait_ticks,
    risk_money_from_stops,
    should_enter_cooldown,
    theoretical_lot_from_risk,
    validate_confluence,
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

    # A. Timeframe independence
    for chart in ("PERIOD_M1", "PERIOD_M5", "PERIOD_M15", "PERIOD_H1"):
        locked = lock_strategy_timeframes(chart)
        check(
            f"tester {chart} still H4/M15/M1",
            locked == {"htf": HTF_TIMEFRAME, "setup": SETUP_TIMEFRAME, "execution": EXECUTION_TIMEFRAME},
        )

    # B. Risk money mode
    tick, tv = 0.01, 1.0
    # Gold-like large SL from existing 29/07 fixture
    wide_sl = abs(4019.53 - 4034.94)  # 15.41

    for balance, max_risk in ((100.0, 5.0), (100.0, 10.0), (200.0, 10.0), (1800.0, 10.0)):
        allowed = allowed_risk_money(False, max_risk, 5.0, balance)
        check(f"FIXED_MONEY ${balance:.0f} max=${max_risk:.0f}", abs(allowed - max_risk) < 1e-12)

    pct = allowed_risk_money(True, 10.0, 5.0, 200.0)
    check("PERCENT 5% of $200 = $10", abs(pct - 10.0) < 1e-12)

    # C. Minimum lot vs max risk (wide Gold SL)
    theo, lot, actual, rej = lot_from_allowed_risk(tick, tv, wide_sl, 5.0)
    check(
        "C $100/$5 wide SL → NO TRADE min lot exceeds risk",
        lot == 0.0 and "minimum lot exceeds risk limit" in rej,
        f"theo={theo:.4f} actual={actual:.2f}",
    )
    theo10, lot10, actual10, rej10 = lot_from_allowed_risk(tick, tv, wide_sl, 10.0)
    check(
        "C $100/$10 wide SL still NO TRADE if 0.01 loses ~$15",
        lot10 == 0.0 and "minimum lot exceeds risk limit" in rej10,
        f"min_risk={actual10:.2f}",
    )

    # Narrow SL: 5.0 distance → 0.01 lot risks $5
    theo_n, lot_n, actual_n, rej_n = lot_from_allowed_risk(tick, tv, 5.0, 10.0)
    check(
        "C $10 max with SL=$5/0.01 → TRADE 0.01",
        rej_n == "" and abs(lot_n - 0.01) < 1e-12 and actual_n <= 10.0 + 1e-8,
        f"lot={lot_n} risk={actual_n:.2f}",
    )
    _, lot5, actual5, rej5 = lot_from_allowed_risk(tick, tv, 5.0, 5.0)
    check(
        "C $5 max with SL=$5/0.01 → TRADE 0.01",
        rej5 == "" and abs(lot5 - 0.01) < 1e-12 and abs(actual5 - 5.0) < 1e-8,
    )

    # D. Maximum lot never > 0.01
    theo_big, lot_cap, actual_big, rej_cap = lot_from_allowed_risk(tick, tv, 1.0, 1000.0)
    check("D theoretical can exceed 0.01", theo_big > 0.01)
    check("D final lot never > 0.01", lot_cap <= HARD_MAX_LOT + 1e-12)
    check("D clamp 0.05 → 0.01", abs(clamp_lot_hard_cap(0.05) - 0.01) < 1e-12)

    # E. R formula uses SL distance
    rm = risk_money_from_stops(tick, tv, 4019.53, 4034.94, 0.01)
    r = realized_r(-15.42, rm)
    old_bug = realized_r(-15.42, 0.01 * tv)
    check("E risk_money includes SL distance ≈ 15.41", abs(rm - 15.41) < 1e-6)
    check("E R ≈ -1 not -1542", abs(r + 1.0) < 0.02)
    check("E old volume*tick_value bug remains rejected", abs(old_bug + 1542.0) < 1.0)

    # F. Margin rejection before send
    ok_m, why_m = margin_is_sufficient(80.0, 50.0)
    check("F insufficient margin rejected", (not ok_m) and why_m == "insufficient margin")
    ok_ok, _ = margin_is_sufficient(40.0, 50.0)
    check("F sufficient margin allowed", ok_ok)

    # G. 2 SL cooldown — third trade blocked for 8h
    c = 0
    c = c + 1
    c = c + 1
    start = 1_704_067_200
    end = cooldown_end_from_start(start, 8)
    check("G 2 SL starts cooldown", should_enter_cooldown(c, 2))
    check("G duration is 8h", end - start == 8 * 3600)
    check("G blocked 1s before 8h", is_cooldown_active(end - 1, end))
    check("G allowed at exactly 8h", not is_cooldown_active(end, end))
    cfg = default_cfg()
    s = perfect_buy_setup()
    ok_block, reason_cd = validate_confluence(s, cfg, False, 0, 10, True, True)
    check(
        "G third trade MUST BE BLOCKED during cooldown",
        (not ok_block) and "cooldown" in reason_cd.lower(),
        reason_cd,
    )
    ok_resume, _ = validate_confluence(s, cfg, True, 0, 10, True, True)
    check("G after 8h trading may resume", ok_resume)

    # Fixed money must not silently become 1% of balance
    check(
        "FIXED_MONEY ignores percent and balance ($100 still $10)",
        abs(allowed_risk_money(False, 10.0, 1.0, 100.0) - 10.0) < 1e-12,
    )
    check(
        "default InpRiskMoney=10 when risk_money unset",
        abs(allowed_risk_money(False, 0.0, 1.0, 100.0) - 10.0) < 1e-12,
    )
    theo_wide = theoretical_lot_from_risk(tick, tv, wide_sl, 10.0)
    check(
        "theoretical lot $10 / 15.41 ≈ 0.0065",
        abs(theo_wide - (10.0 / ((wide_sl / tick) * tv))) < 1e-9,
        f"theo={theo_wide:.6f}",
    )

    # H. IFVG waiting-for-retest lifecycle
    wait = create_ifvg_setup(8715446097785671798, 1_774_000_000, 14_400)
    replay_zone_wait_ticks(wait, 1_774_000_001, TESTER_WAIT_TICKS, fixed=True)
    check("H stays WAITING_RETEST while price is outside IFVG", wait["state"] == ST_WAITING_RETEST)
    check("H does not spam Entry validation", LOG_ENTRY_VALIDATION not in "".join(wait["logs"]))
    process_ifvg_tick(wait, 1_774_000_061, retest_ok=True)
    check("H price return advances to entry validation", wait["state"] != ST_IDLE and wait["setup_id"] == 8715446097785671798)

    # I. IFVG expiration lifecycle
    expired = create_ifvg_setup(-5672277183617112785, 1_000, 10)
    expired["state"] = "ENTRY_VALIDATION"
    replay_expired_ifvg_ticks(expired, 1_010, 30, fixed=True)
    check("I expired IFVG returns IDLE", expired["state"] == ST_IDLE)
    check("I expired SetupID is cleared", expired["setup_id"] == 0)
    check("I expired IFVG is not re-validated", not expired["entry_validation_calls"])

    print(f"\npassed={passed} failed={failed}")
    return failed


if __name__ == "__main__":
    raise SystemExit(run())
