#!/usr/bin/env python3
"""Expired IFVG must leave the state machine instead of blocking Entry validation."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from ifvg_safety import (
    LOG_CLEAR,
    LOG_ENTRY_VALIDATION,
    LOG_EXPIRED,
    LOG_IDLE,
    LOG_INVALIDATE,
    ST_ENTRY_VALIDATION,
    ST_IDLE,
    ST_WAITING_RETEST,
    after_entry_reject,
    create_ifvg_setup,
    ifvg_expire_at,
    ifvg_validity_elapsed,
    process_ifvg_tick,
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

    created = 1_000
    validity = 10
    old_id = -5672277183617112785
    setup = create_ifvg_setup(old_id, created, validity)

    check("IFVG created", setup["ifvg_id"] == 1 and setup["setup_id"] == old_id)
    check("IFVG starts WAITING_RETEST", setup["state"] == ST_WAITING_RETEST)
    check(
        "expire = created + InpIFVGValiditySeconds",
        setup["expire"] == ifvg_expire_at(created, validity) == created + validity,
    )
    check("not elapsed before validity", not ifvg_validity_elapsed(created + 9, created, validity, setup["ifvg_life"]))
    check("elapsed at validity", ifvg_validity_elapsed(created + validity, created, validity, setup["ifvg_life"]))

    process_ifvg_tick(setup, now=created + 5, retest_ok=True)
    check("retest before expiry → ENTRY_VALIDATION", setup["state"] == ST_ENTRY_VALIDATION)
    check("one Entry validation before expiry", setup["entry_validation_calls"] == [old_id])

    process_ifvg_tick(setup, now=created + validity)
    check("expiration invalidates setup", setup["state"] == ST_IDLE)
    check("SetupID cleared", setup["setup_id"] == 0)
    check("active IFVG cleared", setup["ifvg_id"] == 0)
    check("IDLE waiting for new setup", setup["can_search_new"] is True)
    check("EXPIRED log", any(LOG_EXPIRED in line and str(old_id) in line for line in setup["logs"]))
    check("INVALIDATE log", LOG_INVALIDATE in setup["logs"])
    check("CLEAR ACTIVE SETUP log", LOG_CLEAR in setup["logs"])
    check("IDLE log", LOG_IDLE in setup["logs"])

    calls_at_expiry = list(setup["entry_validation_calls"])
    process_ifvg_tick(setup, now=created + validity + 1)
    process_ifvg_tick(setup, now=created + validity + 2)
    process_ifvg_tick(setup, now=created + validity + 3)
    check(
        "no repetitive Entry validation for expired SetupID",
        setup["entry_validation_calls"] == calls_at_expiry and old_id not in setup["entry_validation_calls"][1:],
    )
    check(
        "Entry validation log not repeated after expiry",
        sum(1 for line in setup["logs"] if line.startswith(LOG_ENTRY_VALIDATION) and str(old_id) in line) == 1,
    )

    new_id = 42
    nxt = create_ifvg_setup(new_id, created=created + validity + 5, validity_seconds=validity)
    check("new setup can be searched after IDLE", nxt["state"] == ST_WAITING_RETEST and nxt["setup_id"] == new_id)
    process_ifvg_tick(nxt, now=created + validity + 6, retest_ok=True)
    check("new SetupID may enter Entry validation", nxt["entry_validation_calls"] == [new_id])
    check("old SetupID still absent from new setup", old_id not in nxt["entry_validation_calls"])

    waiting = create_ifvg_setup(old_id, created, validity)
    process_ifvg_tick(waiting, now=created + validity, retest_ok=False)
    check("WAITING_RETEST expiry → IDLE without Entry validation", waiting["state"] == ST_IDLE)
    check("WAITING_RETEST expiry clears SetupID", waiting["setup_id"] == 0)
    check("WAITING_RETEST expiry has zero Entry validation calls", waiting["entry_validation_calls"] == [])

    check(
        "entry reject validity elapsed → IDLE",
        after_entry_reject(ST_ENTRY_VALIDATION, "IFVG validity period elapsed") == ST_IDLE,
    )
    check(
        "entry reject cooldown stays in ENTRY_VALIDATION",
        after_entry_reject(ST_ENTRY_VALIDATION, "8H cooldown active") == ST_ENTRY_VALIDATION,
    )
    check(
        "entry reject without retest returns WAITING_RETEST",
        after_entry_reject(ST_ENTRY_VALIDATION, "IFVG without retest") == ST_WAITING_RETEST,
    )

    print(f"\npassed={passed} failed={failed}")
    return failed


if __name__ == "__main__":
    raise SystemExit(run())
