#!/usr/bin/env python3
"""Lifecycle + R-reporting tests (no strategy-filter changes)."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from ifvg_safety import (
    ST_CISD_VALIDATED,
    ST_COOLDOWN,
    ST_ENTRY_VALIDATION,
    ST_FVG_DETECTED,
    ST_IDLE,
    ST_ORDER_SENT,
    ST_POSITION_ACTIVE,
    ST_WAITING_RETEST,
    after_cooldown,
    after_entry_reject,
    after_position_closed,
    after_stage_fail,
    cooldown_end_from_start,
    is_cooldown_active,
    realized_r,
    reward_meets_target,
    risk_money_from_stops,
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

    check("close ORDER_SENT → IDLE", after_position_closed(ST_ORDER_SENT) == ST_IDLE)
    check("close POSITION_ACTIVE → IDLE", after_position_closed(ST_POSITION_ACTIVE) == ST_IDLE)
    check("close does not skip a live CISD wait", after_position_closed(ST_CISD_VALIDATED) == ST_CISD_VALIDATED)

    check(
        "CISD fail while window open stays in CISD (wait, do not promote)",
        after_stage_fail(ST_CISD_VALIDATED, False) == ST_CISD_VALIDATED,
    )
    check("CISD fail after window → IDLE", after_stage_fail(ST_CISD_VALIDATED, True) == ST_IDLE)
    check(
        "Displacement fail while window open stays (wait, do not promote)",
        after_stage_fail(ST_CISD_VALIDATED, False) == ST_CISD_VALIDATED,
    )
    check("Displacement fail after window → IDLE", after_stage_fail(ST_CISD_VALIDATED, True) == ST_IDLE)
    check("FVG/inversion fail while window open stays", after_stage_fail(ST_FVG_DETECTED, False) == ST_FVG_DETECTED)
    check("FVG/inversion fail after window → IDLE", after_stage_fail(ST_FVG_DETECTED, True) == ST_IDLE)

    check("2 SL cooldown state", after_cooldown(ST_IDLE, True) == ST_COOLDOWN)
    check("cooldown expired → IDLE", after_cooldown(ST_COOLDOWN, False) == ST_IDLE)
    check(
        "IFVG validity elapsed from ENTRY_VALIDATION → IDLE",
        after_entry_reject(ST_ENTRY_VALIDATION, "IFVG validity period elapsed") == ST_IDLE,
    )
    check(
        "IFVG without retest still returns WAITING_RETEST",
        after_entry_reject(ST_ENTRY_VALIDATION, "IFVG without retest") == ST_WAITING_RETEST,
    )
    check(
        "price outside IFVG waits, does not stay in ENTRY_VALIDATION",
        after_entry_reject(ST_ENTRY_VALIDATION, "price has not returned into IFVG zone")
        == ST_WAITING_RETEST,
    )
    start = 1_704_067_200
    end = cooldown_end_from_start(start, 8)
    check("cooldown duration is exactly 8h", end - start == 8 * 3600)
    check("no entry 1s before 8h", is_cooldown_active(end - 1, end))
    check("entry allowed at exactly 8h", not is_cooldown_active(end, end))

    entry, sl, tp = 4019.53, 4034.94, 3973.30
    risk_money = risk_money_from_stops(0.01, 1.0, entry, sl, 0.01)
    r = realized_r(-15.42, risk_money)
    old_bug = realized_r(-15.42, 0.01 * 1.0)
    gate_ok, gate_rr = reward_meets_target(entry, sl, tp, 3.0)
    check("29/07 risk_money ≈ 15.41", abs(risk_money - 15.41) < 1e-6, f"{risk_money:.5f}")
    check("29/07 SL ≈ -1R", abs(r + 1.0) < 0.02, f"{r:.5f}")
    check("old volume*tick_value bug is -1542R", abs(old_bug + 1542.0) < 1.0, f"{old_bug:.3f}")
    check("RR entry gate unchanged 1:3", gate_ok and abs(gate_rr - 3.0) < 0.01, f"{gate_rr:.4f}")

    print(f"\npassed={passed} failed={failed}")
    return failed


if __name__ == "__main__":
    raise SystemExit(run())
