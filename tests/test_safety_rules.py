#!/usr/bin/env python3
"""Mandatory TEST 1–10 plus extra hard-cap protections."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from ifvg_safety import (
    FVG_CREATED,
    IFVG_WAITING,
    can_open_new_position,
    clamp_lot_hard_cap,
    clamp_lot_input,
    clamp_max_positions,
    cooldown_end_from_start,
    default_cfg,
    is_cooldown_active,
    on_position_closed_sl,
    on_position_closed_win,
    perfect_buy_setup,
    reward_meets_target,
    should_enter_cooldown,
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

    # TEST 1
    check("TEST 1 lot 0.05 -> 0.01", abs(clamp_lot_hard_cap(0.05) - 0.01) < 1e-12)

    # TEST 2
    check("TEST 2 two positions block new trade", not can_open_new_position(2, 2))

    # TEST 3
    check("TEST 3 one position allows a second", can_open_new_position(1, 2))

    # TEST 4
    c = 0
    c = on_position_closed_sl(c)
    c = on_position_closed_sl(c)
    start = 1_704_067_200  # 2024-01-01 00:00 UTC
    end = cooldown_end_from_start(start, 8)
    check(
        "TEST 4 two SL start 8h cooldown",
        should_enter_cooldown(c, 2) and end - start == 8 * 3600,
    )

    # TEST 5
    check(
        "TEST 5 no trade during cooldown",
        is_cooldown_active(start + 3 * 3600, start + 8 * 3600),
    )

    cfg = default_cfg()
    s = perfect_buy_setup()
    s["fvg_state"] = FVG_CREATED
    ok, reason = validate_confluence(s, cfg, True, 0, 10, True, True)
    check("TEST 6 FVG without inversion", (not ok) and "inversion" in reason.lower())

    s = perfect_buy_setup()
    s["ifvg_life"] = IFVG_WAITING
    ok, reason = validate_confluence(s, cfg, True, 0, 10, True, False)
    check("TEST 7 IFVG without retest", (not ok) and "retest" in reason.lower())

    s = perfect_buy_setup()
    s["smt_valid"] = False
    ok, reason = validate_confluence(s, cfg, True, 0, 10, True, True)
    check("TEST 8 SMT missing while required", (not ok) and "SMT" in reason)

    ok9, actual9 = reward_meets_target(2000.0, 1990.0, 2024.0, 3.0)
    check("TEST 9 RR 1:2.4 rejected vs target 3", (not ok9) and abs(actual9 - 2.4) < 1e-9)

    ok10, actual10 = reward_meets_target(2000.0, 1990.0, 2032.0, 3.0)
    check("TEST 10 RR 1:3.2 accepted vs target 3", ok10 and abs(actual10 - 3.2) < 1e-9)

    check("HARD CAP input 0.10 -> 0.01", abs(clamp_lot_input(0.10) - 0.01) < 1e-12)
    check("HARD CAP positions 99 -> 2", clamp_max_positions(99) == 2)
    check("NO third position even if input allows", not can_open_new_position(2, 99))
    check("Win resets consecutive SL", on_position_closed_win(2) == 0)
    check("Lot 0.02 blocked by hard cap", abs(clamp_lot_hard_cap(0.02) - 0.01) < 1e-12)
    check("Cooldown 4h input still 8h", cooldown_end_from_start(0, 4) == 8 * 3600)

    s = perfect_buy_setup()
    ok, reason = validate_confluence(s, cfg, False, 0, 10, True, True)
    check("Perfect setup during cooldown blocked", (not ok) and "cooldown" in reason.lower())

    print(f"\npassed={passed} failed={failed}")
    return failed


if __name__ == "__main__":
    raise SystemExit(run())
