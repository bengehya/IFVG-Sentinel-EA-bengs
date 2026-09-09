#!/usr/bin/env python3
"""Regression: price outside IFVG is WAITING_FOR_RETEST, not an Entry validation loop."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from ifvg_safety import (
    IFVG_LIFE_RETEST_LIFE,
    IFVG_LIFE_WAITING,
    LOG_NO_TRADE_ZONE,
    LOG_WAITING_FOR_RETEST,
    ST_ENTRY_VALIDATION,
    ST_IDLE,
    ST_WAITING_RETEST,
    TESTER_EXPIRED_SETUP_ID,
    TESTER_LOOP_TICKS,
    TESTER_WAIT_SETUP_ID,
    TESTER_WAIT_TICKS,
    after_entry_reject,
    after_entry_reject_buggy,
    create_ifvg_setup,
    is_waiting_for_retest_reason,
    process_ifvg_tick,
    replay_expired_ifvg_ticks,
    replay_zone_wait_ticks,
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

    created = 1_774_000_000  # 2026.04.24 12:58-ish
    validity = 14_400
    sid = TESTER_WAIT_SETUP_ID

    setup = create_ifvg_setup(sid, created, validity)
    check("1. IFVG created", setup["ifvg_id"] == 1)
    check("2. SetupID assigned", setup["setup_id"] == sid)
    check("3. starts WAITING_RETEST", setup["state"] == ST_WAITING_RETEST)

    replay_zone_wait_ticks(setup, created + 1, TESTER_WAIT_TICKS, fixed=True)
    check("4. still active after many outside-zone ticks", setup["state"] == ST_WAITING_RETEST)
    check("5. SetupID unchanged while waiting", setup["setup_id"] == sid)
    check("6. not invalidated by price outside IFVG", setup["ifvg_id"] == 1 and setup["ifvg_life"] == IFVG_LIFE_WAITING)
    check(
        "7. no Entry validation loop while waiting",
        setup["entry_validation_calls"] == [],
    )
    wait_logs = [line for line in setup["logs"] if line.startswith(LOG_WAITING_FOR_RETEST)]
    check("waiting log once, not per tick", len(wait_logs) == 1, f"n={len(wait_logs)}")
    check("no NO TRADE zone spam", LOG_NO_TRADE_ZONE not in setup["logs"])

    process_ifvg_tick(setup, created + TESTER_WAIT_TICKS + 2, retest_ok=True)
    check("8. retest evaluated when price enters zone", setup["ifvg_life"] == IFVG_LIFE_RETEST_LIFE)
    check("9. proceeds to Entry validation", setup["state"] == ST_ENTRY_VALIDATION)
    check("10. one Entry validation after retest", setup["entry_validation_calls"] == [sid])

    process_ifvg_tick(setup, created + validity, retest_ok=False)
    check("11. expiration invalidates", setup["state"] == ST_IDLE)
    check("12a. SetupID cleared after expiry", setup["setup_id"] == 0)
    check("12b. IFVG/retest cleared", setup["ifvg_id"] == 0)
    check("12c. IDLE after expiry", setup["can_search_new"] is True)

    nxt = create_ifvg_setup(99, created + validity + 10, validity)
    check("13. future setup gets a NEW SetupID", nxt["setup_id"] == 99 and nxt["setup_id"] != sid)

    # Reproduce the tester journal loop vs the fix.
    buggy = create_ifvg_setup(sid, created, validity)
    buggy["state"] = ST_ENTRY_VALIDATION
    buggy["ifvg_life"] = IFVG_LIFE_RETEST_LIFE
    replay_zone_wait_ticks(buggy, created + 1, TESTER_WAIT_TICKS, fixed=False)
    check(
        "OLD BUG: Entry validation every tick for same SetupID",
        buggy["entry_validation_calls"] == [sid] * TESTER_WAIT_TICKS,
    )
    check(
        "OLD BUG: NO TRADE — price has not returned into IFVG zone every tick",
        sum(1 for line in buggy["logs"] if line == LOG_NO_TRADE_ZONE) == TESTER_WAIT_TICKS,
    )
    check(
        "OLD BUG: stays in ENTRY_VALIDATION",
        buggy["state"] == ST_ENTRY_VALIDATION and buggy["setup_id"] == sid,
    )
    check(
        "OLD reject handler does not treat zone wait as wait",
        after_entry_reject_buggy(ST_ENTRY_VALIDATION, "price has not returned into IFVG zone")
        == ST_ENTRY_VALIDATION,
    )

    fixed = create_ifvg_setup(sid, created, validity)
    fixed["state"] = ST_ENTRY_VALIDATION
    replay_zone_wait_ticks(fixed, created + 1, TESTER_WAIT_TICKS, fixed=True)
    check("FIX: leaves ENTRY_VALIDATION for WAITING_RETEST", fixed["state"] == ST_WAITING_RETEST)
    check("FIX: SetupID kept while waiting", fixed["setup_id"] == sid)
    check("FIX: zero Entry validation calls while price outside", fixed["entry_validation_calls"] == [])
    check(
        "FIX: zone wait is WAITING_FOR_RETEST",
        after_entry_reject(ST_ENTRY_VALIDATION, "price has not returned into IFVG zone")
        == ST_WAITING_RETEST,
    )
    check(
        "WAIT vs EXPIRE remain distinct",
        is_waiting_for_retest_reason("price has not returned into IFVG zone")
        and not is_waiting_for_retest_reason("IFVG validity period elapsed"),
    )

    # Previous expiration regression still holds.
    exp = create_ifvg_setup(TESTER_EXPIRED_SETUP_ID, created, validity)
    exp["state"] = ST_ENTRY_VALIDATION
    exp["ifvg_life"] = IFVG_LIFE_RETEST_LIFE
    replay_expired_ifvg_ticks(exp, created + validity, TESTER_LOOP_TICKS, fixed=True)
    check("expiration regression: IDLE", exp["state"] == ST_IDLE)
    check("expiration regression: SetupID cleared", exp["setup_id"] == 0)
    check(
        "expiration regression: no Entry validation of expired id",
        TESTER_EXPIRED_SETUP_ID not in exp["entry_validation_calls"],
    )

    print(f"\npassed={passed} failed={failed}")
    return failed


if __name__ == "__main__":
    raise SystemExit(run())
