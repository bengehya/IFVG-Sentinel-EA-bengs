"""IFVG Sentinel — Python mirror of hardcoded MQL5 safety rules.

These tests do not replace MetaEditor compilation. They prove the
capital-protection policy cannot be bypassed at the logic layer.
"""

from __future__ import annotations

HARD_MAX_LOT = 0.01
HARD_MAX_POSITIONS = 2
HARD_MIN_CONSEC_SL = 2
HARD_MIN_COOLDOWN_HOURS = 8
SECONDS_PER_HOUR = 3600


def clamp_lot_hard_cap(requested_lot: float) -> float:
    if requested_lot <= 0.0:
        return 0.0
    return min(requested_lot, HARD_MAX_LOT)


def clamp_lot_input(input_max_lot: float) -> float:
    if input_max_lot <= 0.0:
        return HARD_MAX_LOT
    return min(input_max_lot, HARD_MAX_LOT)


def clamp_max_positions(input_max_positions: int) -> int:
    v = input_max_positions
    if v <= 0:
        v = HARD_MAX_POSITIONS
    if v > HARD_MAX_POSITIONS:
        v = HARD_MAX_POSITIONS
    return v


def clamp_consec_sl(input_limit: int) -> int:
    return max(input_limit, HARD_MIN_CONSEC_SL)


def clamp_cooldown_hours(input_hours: int) -> int:
    return max(input_hours, HARD_MIN_COOLDOWN_HOURS)


def can_open_new_position(open_positions: int, max_positions: int) -> bool:
    cap = clamp_max_positions(max_positions)
    if open_positions < 0:
        return False
    return open_positions < cap


def is_cooldown_active(now: int, cooldown_end: int) -> bool:
    if cooldown_end <= 0:
        return False
    return now < cooldown_end


def cooldown_end_from_start(start: int, hours: int) -> int:
    return start + clamp_cooldown_hours(hours) * SECONDS_PER_HOUR


def on_position_closed_sl(consecutive_losses: int) -> int:
    return consecutive_losses + 1


def on_position_closed_win(_consecutive_losses: int) -> int:
    return 0


def should_enter_cooldown(consecutive_losses: int, limit: int) -> bool:
    return consecutive_losses >= clamp_consec_sl(limit)


def volume_respects_hard_cap(lot: float) -> bool:
    if lot <= 0.0:
        return False
    return lot <= HARD_MAX_LOT + 1e-12


def reward_meets_target(entry: float, sl: float, tp: float, target_rr: float) -> tuple[bool, float]:
    risk = abs(entry - sl)
    reward = abs(tp - entry)
    if risk <= 0.0:
        return False, 0.0
    actual = reward / risk
    return actual + 1e-9 >= target_rr, actual


def stops_consistent(direction: int, entry: float, sl: float, tp: float) -> bool:
    if direction == 1:
        return sl < entry < tp
    if direction == -1:
        return sl > entry > tp
    return False


# --- confluence gate (mirrors CSetupValidator) ---

FVG_CREATED = 1
FVG_INVERTED = 5
IFVG_NONE = 0
IFVG_WAITING = 2
IFVG_RETEST = 3
BIAS_NONE = 0
BIAS_BULL = 1
BIAS_BEAR = -1
BIAS_NEUTRAL = 2
SMT_REQUIRED = 2


def dir_matches_bias(direction: int, bias: int) -> bool:
    return (direction == 1 and bias == BIAS_BULL) or (direction == -1 and bias == BIAS_BEAR)


def validate_confluence(setup: dict, cfg: dict, cooldown_ok: bool, open_positions: int,
                        spread_points: float, session_ok: bool, ifvg_retest_ok: bool) -> tuple[bool, str]:
    if not cooldown_ok:
        return False, "8H cooldown active"
    if not can_open_new_position(open_positions, cfg["max_positions"]):
        return False, "2 positions already open"
    if not session_ok:
        return False, "session not allowed"
    if spread_points > cfg["max_spread_points"]:
        return False, "spread too high"
    if setup["htf_bias"] in (BIAS_NONE, BIAS_NEUTRAL) or not dir_matches_bias(setup["direction"], setup["htf_bias"]):
        if setup["htf_bias"] in (BIAS_NONE, BIAS_NEUTRAL):
            return False, "HTF context invalid"
        return False, "direction not aligned with HTF bias"
    if not setup["liquidity_active"] and not setup["sweep_valid"]:
        return False, "liquidity not identified"
    if not setup["sweep_valid"]:
        return False, "liquidity sweep not confirmed"
    if cfg.get("gold_only_mode"):
        pass
    elif cfg.get("smt_mode") == SMT_REQUIRED and not setup.get("smt_valid"):
        return False, "SMT missing"
    if not setup["cisd_valid"]:
        return False, "CISD not confirmed"
    if not setup["displacement"]:
        return False, "displacement not confirmed"
    if setup["fvg_id"] == 0 or setup["fvg_state"] not in (FVG_INVERTED, 3):
        return False, "FVG without inversion"
    if setup["ifvg_id"] == 0 or setup["ifvg_life"] == IFVG_NONE:
        return False, "IFVG not created"
    if not ifvg_retest_ok:
        return False, "IFVG without retest"
    if setup["direction"] == 0:
        return False, "direction incoherent"
    if setup["executed"]:
        return False, "setup already executed"
    return True, ""


def perfect_buy_setup() -> dict:
    return {
        "htf_bias": BIAS_BULL,
        "direction": 1,
        "liquidity_active": True,
        "sweep_valid": True,
        "smt_valid": True,
        "cisd_valid": True,
        "displacement": True,
        "fvg_id": 1,
        "fvg_state": FVG_INVERTED,
        "ifvg_id": 1,
        "ifvg_life": IFVG_RETEST,
        "executed": False,
    }


def default_cfg() -> dict:
    return {
        "max_positions": 2,
        "max_spread_points": 50,
        "smt_mode": SMT_REQUIRED,
        "gold_only_mode": False,
        "symbol": "XAUUSD",
        "smt_symbol1": "XAGUSD",
        "smt_symbol2": "USDX",
    }


def allows_order_on_symbol(trading_symbol: str, order_symbol: str) -> bool:
    if not trading_symbol or not order_symbol:
        return False
    return trading_symbol == order_symbol


def is_external_compare_symbol(order_symbol: str, smt_symbol1: str, smt_symbol2: str) -> bool:
    if not order_symbol:
        return False
    return order_symbol in (smt_symbol1, smt_symbol2) and order_symbol != ""


def smt_status_for_mode(gold_only: bool, smt_valid: bool) -> str:
    if gold_only:
        return "SKIPPED_GOLD_ONLY"
    return "PASS" if smt_valid else "FAIL"


# --- reporting R (mirrors CIFVGSafety::RiskMoneyFromDistance) ---

def risk_money_from_distance(tick_size: float, tick_value: float, risk_distance: float, volume: float) -> float:
    if tick_size <= 0.0 or tick_value <= 0.0 or risk_distance <= 0.0 or volume <= 0.0:
        return 0.0
    return (risk_distance / tick_size) * tick_value * volume


def risk_money_from_stops(tick_size: float, tick_value: float, entry: float, sl: float, volume: float) -> float:
    return risk_money_from_distance(tick_size, tick_value, abs(entry - sl), volume)


def realized_r(profit: float, risk_money: float) -> float:
    if risk_money <= 0.0:
        return 0.0
    return profit / risk_money


# --- state-machine lifecycle (not strategy filters) ---

ST_IDLE = "IDLE"
ST_ORDER_SENT = "ORDER_SENT"
ST_POSITION_ACTIVE = "POSITION_ACTIVE"
ST_POSITION_CLOSED = "POSITION_CLOSED"
ST_CISD_VALIDATED = "CISD_VALIDATED"
ST_FVG_DETECTED = "FVG_DETECTED"
ST_COOLDOWN = "COOLDOWN"


def after_position_closed(state: str) -> str:
    if state in (ST_ORDER_SENT, ST_POSITION_ACTIVE, ST_POSITION_CLOSED):
        return ST_IDLE
    return state


def after_stage_fail(state: str, window_expired: bool) -> str:
    """A fail stays a fail. Only return to IDLE when the wait window is exhausted."""
    if window_expired:
        return ST_IDLE
    return state


def after_cooldown(state: str, cooldown_active: bool) -> str:
    if cooldown_active:
        return ST_COOLDOWN
    if state == ST_COOLDOWN:
        return ST_IDLE
    return state


# --- expired IFVG setup lifecycle (not strategy filters) ---

ST_IFVG_CREATED = "IFVG_CREATED"
ST_WAITING_RETEST = "WAITING_RETEST"
ST_RETEST_DETECTED = "RETEST_DETECTED"
ST_ENTRY_VALIDATION = "ENTRY_VALIDATION"

IFVG_LIFE_CREATED = "CREATED"
IFVG_LIFE_WAITING = "WAITING_RETEST"
IFVG_LIFE_RETEST_LIFE = "RETEST"
IFVG_LIFE_EXPIRED_LIFE = "EXPIRED"
IFVG_LIFE_NONE_LIFE = "NONE"

LOG_EXPIRED = "[IFVG] EXPIRED — SetupID="
LOG_INVALIDATE = "[STATE] INVALIDATE — reason=IFVG_VALIDITY_EXPIRED"
LOG_CLEAR = "[STATE] CLEAR ACTIVE SETUP"
LOG_IDLE = "[STATE] IDLE — waiting for new setup"
LOG_ENTRY_VALIDATION = "[IFVG] Entry validation: SetupID="
LOG_NO_TRADE_ELAPSED = "[IFVG] NO TRADE — IFVG validity period elapsed"
LOG_WAITING_FOR_RETEST = "[IFVG] WAITING_FOR_RETEST: SetupID="
LOG_NO_TRADE_ZONE = "[IFVG] NO TRADE — price has not returned into IFVG zone"

# Tester evidence: same SetupID re-validated for several minutes after expiry.
TESTER_EXPIRED_SETUP_ID = -5672277183617112785
TESTER_LOOP_TICKS = 180  # ~3 minutes of 1s ticks after validity elapsed

# Tester evidence: ST_ENTRY_VALIDATION wait-loop while price is outside the IFVG.
TESTER_WAIT_SETUP_ID = 8715446097785671798
TESTER_WAIT_TICKS = 60


def ifvg_expire_at(created: int, validity_seconds: int) -> int:
    return created + validity_seconds


def ifvg_validity_elapsed(now: int, created: int, validity_seconds: int, life: str) -> bool:
    if life == IFVG_LIFE_EXPIRED_LIFE:
        return True
    if life in ("TRADED", "INVALIDATED", IFVG_LIFE_NONE_LIFE):
        return False
    expire = ifvg_expire_at(created, validity_seconds)
    return expire > 0 and now >= expire


def create_ifvg_setup(setup_id: int, created: int, validity_seconds: int) -> dict:
    """Mirrors IFVG created → WAITING_RETEST (CIFVGManager::CreateFromInvertedFVG)."""
    return {
        "setup_id": setup_id,
        "state": ST_WAITING_RETEST,
        "ifvg_id": 1,
        "ifvg_life": IFVG_LIFE_WAITING,
        "ifvg_created": created,
        "validity_seconds": validity_seconds,
        "expire": ifvg_expire_at(created, validity_seconds),
        "can_search_new": False,
        "entry_validation_calls": [],
        "logs": [],
        "last_wait_fp": "",
    }


def _invalidate_expired(setup: dict) -> None:
    sid = setup["setup_id"]
    setup["logs"].append(f"{LOG_EXPIRED}{sid}")
    setup["logs"].append(LOG_INVALIDATE)
    setup["logs"].append(LOG_CLEAR)
    setup["ifvg_life"] = IFVG_LIFE_NONE_LIFE
    setup["ifvg_id"] = 0
    setup["setup_id"] = 0
    setup["state"] = ST_IDLE
    setup["can_search_new"] = True
    setup["logs"].append(LOG_IDLE)


def _log_waiting_once(setup: dict) -> None:
    fp = f"WAITING_FOR_RETEST|{setup['setup_id']}"
    if setup.get("last_wait_fp") == fp:
        return
    setup["last_wait_fp"] = fp
    setup["logs"].append(f"{LOG_WAITING_FOR_RETEST}{setup['setup_id']}")


def process_ifvg_tick(setup: dict, now: int, retest_ok: bool = False) -> dict:
    """Mirrors CStateMachine::Process for WAITING_RETEST / ENTRY_VALIDATION.

    Expired IFVG must invalidate, clear SetupID, return IDLE, and never
    re-enter Entry validation with the old SetupID.

    Price outside the IFVG is WAITING_FOR_RETEST, not an entry failure.
    """
    tick_state = setup["state"] in (ST_WAITING_RETEST, ST_RETEST_DETECTED, ST_ENTRY_VALIDATION)
    if tick_state and ifvg_validity_elapsed(
        now, setup["ifvg_created"], setup["validity_seconds"], setup["ifvg_life"]
    ):
        _invalidate_expired(setup)
        return setup

    if setup["state"] == ST_WAITING_RETEST:
        if retest_ok:
            setup["ifvg_life"] = IFVG_LIFE_RETEST_LIFE
            setup["state"] = ST_ENTRY_VALIDATION
        else:
            _log_waiting_once(setup)
            return setup

    if setup["state"] == ST_RETEST_DETECTED:
        setup["state"] = ST_ENTRY_VALIDATION

    if setup["state"] == ST_ENTRY_VALIDATION:
        if ifvg_validity_elapsed(
            now, setup["ifvg_created"], setup["validity_seconds"], setup["ifvg_life"]
        ):
            _invalidate_expired(setup)
            return setup
        if not retest_ok:
            setup["state"] = ST_WAITING_RETEST
            _log_waiting_once(setup)
            return setup
        sid = setup["setup_id"]
        setup["entry_validation_calls"].append(sid)
        setup["logs"].append(f"{LOG_ENTRY_VALIDATION}{sid}")
    return setup


def after_entry_reject_buggy(state: str, reject: str) -> str:
    """Pre-fix ST_ENTRY_VALIDATION else-branch.

    Only cooldown/positions returned early and only 'retest' moved state.
    'IFVG validity period elapsed' matched neither, so the machine stayed
    in ENTRY_VALIDATION and TryEnter ran again on the next tick.
    """
    if "cooldown" in reject or "positions" in reject:
        return state
    if "retest" in reject:
        return ST_WAITING_RETEST
    return state


def is_waiting_for_retest_reason(reason: str) -> bool:
    """Mirrors CIFVGManager::IsWaitingForRetestReason."""
    if "price has not returned into IFVG zone" in reason:
        return True
    if reason == "IFVG without retest":
        return True
    return False


def after_entry_reject(state: str, reject: str) -> str:
    """Mirrors ST_ENTRY_VALIDATION reject handling (lifecycle only)."""
    if "validity period elapsed" in reject or reject == "IFVG_VALIDITY_EXPIRED":
        return ST_IDLE
    if is_waiting_for_retest_reason(reject):
        return ST_WAITING_RETEST
    if "cooldown" in reject or "positions" in reject:
        return state
    if "retest" in reject:
        return ST_WAITING_RETEST
    return state


def try_enter_buggy(setup: dict, now: int) -> bool:
    """Pre-fix CEntryEngine::TryEnter: always logs Entry validation first."""
    sid = setup["setup_id"]
    setup["entry_validation_calls"].append(sid)
    setup["logs"].append(f"{LOG_ENTRY_VALIDATION}{sid}")
    if ifvg_validity_elapsed(
        now, setup["ifvg_created"], setup["validity_seconds"], setup["ifvg_life"]
    ):
        setup["logs"].append(LOG_NO_TRADE_ELAPSED)
        setup["last_reject"] = "IFVG validity period elapsed"
        return False
    return True


def process_expired_loop_tick_buggy(setup: dict, now: int) -> dict:
    """Reproduce the Strategy Tester stall: expired IFVG stays in ENTRY_VALIDATION."""
    if setup["state"] != ST_ENTRY_VALIDATION:
        return setup
    try_enter_buggy(setup, now)
    setup["state"] = after_entry_reject_buggy(setup["state"], setup.get("last_reject", ""))
    return setup


def replay_expired_ifvg_ticks(setup: dict, start_now: int, ticks: int, *, fixed: bool) -> dict:
    """Replay OnTick after validity elapsed. `fixed=False` is the tester loop."""
    for i in range(ticks):
        if fixed:
            process_ifvg_tick(setup, start_now + i)
        else:
            process_expired_loop_tick_buggy(setup, start_now + i)
    return setup


def process_zone_wait_tick_buggy(setup: dict) -> dict:
    """Pre-fix: zone-wait logged as Entry validation failure every tick."""
    if setup["state"] != ST_ENTRY_VALIDATION:
        return setup
    sid = setup["setup_id"]
    setup["entry_validation_calls"].append(sid)
    setup["logs"].append(f"{LOG_ENTRY_VALIDATION}{sid}")
    setup["logs"].append(LOG_NO_TRADE_ZONE)
    setup["last_reject"] = "price has not returned into IFVG zone"
    setup["state"] = after_entry_reject_buggy(setup["state"], setup["last_reject"])
    return setup


def replay_zone_wait_ticks(setup: dict, start_now: int, ticks: int, *, fixed: bool) -> dict:
    """Replay ticks while price stays outside the IFVG."""
    for i in range(ticks):
        if fixed:
            process_ifvg_tick(setup, start_now + i, retest_ok=False)
        else:
            process_zone_wait_tick_buggy(setup)
    return setup
