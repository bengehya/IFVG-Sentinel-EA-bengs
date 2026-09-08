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
