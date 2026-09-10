"""MACHINE MAKER — Python mirror of the MQL5 strategy (not IFVG)."""

from __future__ import annotations

HARD_MAX_LOT = 0.01
HARD_MAX_POSITIONS = 2
HARD_MIN_CONSEC_SL = 2
HARD_MIN_COOLDOWN_H = 8
HARD_TARGET_RR = 4.0
CAPITAL_MULTIPLE = 5.0
DEFAULT_RISK_MONEY = 10.0
TF_DAILY = "PERIOD_D1"
TF_H4 = "PERIOD_H4"
TF_M15 = "PERIOD_M15"

DIR_NONE, DIR_BUY, DIR_SELL = 0, 1, -1
BIAS_NONE, BIAS_BULL, BIAS_BEAR, BIAS_NEUTRAL = 0, 1, -1, 2
MODEL_NONE, MODEL_WICK, MODEL_MID = 0, 1, 2
SL_FVG, SL_FIB62_LARGE, SL_FIB62_SMALL = 1, 2, 3

ST_IDLE = "IDLE"
ST_WAITING_RETEST = "WAITING_FOR_RETEST"
ST_COOLDOWN = "COOLDOWN"
ST_WITHDRAWAL = "WITHDRAWAL_REQUIRED"


def is_gold_symbol(symbol: str) -> bool:
    u = symbol.upper()
    return "XAU" in u or "GOLD" in u


def lock_strategy_timeframes(_chart_tf: str) -> dict:
    return {"daily": TF_DAILY, "h4": TF_H4, "m15": TF_M15}


def bias_from_swings(h0: float, h1: float, l0: float, l1: float) -> int:
    if h0 > h1 and l0 > l1:
        return BIAS_BULL
    if h0 < h1 and l0 < l1:
        return BIAS_BEAR
    return BIAS_NEUTRAL


def align_bias(daily: int, h4: int) -> int:
    if daily == BIAS_BULL and h4 == BIAS_BULL:
        return BIAS_BULL
    if daily == BIAS_BEAR and h4 == BIAS_BEAR:
        return BIAS_BEAR
    return BIAS_NEUTRAL


def build_fib(direction: int, swing_high: float, swing_low: float) -> dict | None:
    if swing_high <= swing_low or direction == DIR_NONE:
        return None
    rng = swing_high - swing_low
    fib50 = swing_low + 0.50 * rng
    if direction == DIR_BUY:
        fib62 = swing_high - 0.62 * rng
        fib00, fib100 = swing_high, swing_low
    else:
        fib62 = swing_low + 0.62 * rng
        fib00, fib100 = swing_low, swing_high
    return {
        "valid": True,
        "direction": direction,
        "swing_high": swing_high,
        "swing_low": swing_low,
        "fib_00": fib00,
        "fib_50": fib50,
        "fib_62": fib62,
        "fib_100": fib100,
    }


def fvg_on_correct_side(direction: int, fib: dict, fvg_high: float, fvg_low: float) -> bool:
    if direction == DIR_BUY:
        return fvg_high < fib["fib_50"]
    if direction == DIR_SELL:
        return fvg_low > fib["fib_50"]
    return False


def three_candle_bullish(c1_high: float, c3_low: float, min_gap: float) -> tuple[float, float] | None:
    if c3_low <= c1_high:
        return None
    hi, lo = c3_low, c1_high
    if hi - lo < min_gap:
        return None
    return hi, lo


def three_candle_bearish(c1_low: float, c3_high: float, min_gap: float) -> tuple[float, float] | None:
    if c3_high >= c1_low:
        return None
    hi, lo = c1_low, c3_high
    if hi - lo < min_gap:
        return None
    return hi, lo


def completely_broken(direction: int, fvg_high: float, fvg_low: float, close: float) -> bool:
    if direction == DIR_BUY:
        return close < fvg_low
    if direction == DIR_SELL:
        return close > fvg_high
    return False


def wick_into_zone(high: float, low: float, fvg_high: float, fvg_low: float) -> bool:
    return low <= fvg_high and high >= fvg_low


def model1(direction: int, candle: dict, fvg_high: float, fvg_low: float) -> tuple[bool, bool, bool]:
    wick_in = wick_into_zone(candle["high"], candle["low"], fvg_high, fvg_low)
    close_out = False
    if not wick_in:
        return False, wick_in, close_out
    if completely_broken(direction, fvg_high, fvg_low, candle["close"]):
        return False, wick_in, close_out
    if fvg_low <= candle["close"] <= fvg_high:
        return False, wick_in, close_out
    if direction == DIR_BUY:
        close_out = candle["close"] > fvg_high
    else:
        close_out = candle["close"] < fvg_low
    return close_out, wick_in, close_out


def model2(direction: int, candle: dict, fvg_high: float, fvg_low: float) -> tuple[bool, bool, bool]:
    mid = 0.5 * (fvg_high + fvg_low)
    touch50 = candle["low"] <= mid <= candle["high"]
    close50 = False
    if not touch50:
        return False, touch50, close50
    if completely_broken(direction, fvg_high, fvg_low, candle["close"]):
        return False, touch50, close50
    if direction == DIR_BUY:
        close50 = candle["close"] > mid
    else:
        close50 = candle["close"] < mid
    return close50, touch50, close50


def detect_entry(direction: int, candle: dict, fvg_high: float, fvg_low: float) -> int:
    ok, _, _ = model1(direction, candle, fvg_high, fvg_low)
    if ok:
        return MODEL_WICK
    ok, _, _ = model2(direction, candle, fvg_high, fvg_low)
    if ok:
        return MODEL_MID
    return MODEL_NONE


def risk_money(tick_size: float, tick_value: float, distance: float, volume: float) -> float:
    if tick_size <= 0 or tick_value <= 0 or distance <= 0 or volume <= 0:
        return 0.0
    return (distance / tick_size) * tick_value * volume


def theoretical_lot(tick_size: float, tick_value: float, distance: float, allowed: float) -> float:
    rpl = (distance / tick_size) * tick_value
    if rpl <= 0 or allowed <= 0:
        return 0.0
    return allowed / rpl


def lot_from_allowed_risk(tick_size: float, tick_value: float, distance: float, allowed: float,
                          volume_min: float = 0.01, volume_step: float = 0.01) -> tuple[float, float, float, str]:
    theo = theoretical_lot(tick_size, tick_value, distance, allowed)
    if theo <= 0:
        return 0.0, 0.0, 0.0, "calculated lot below broker minimum"
    min_risk = risk_money(tick_size, tick_value, distance, volume_min)
    lot = min(theo, HARD_MAX_LOT)
    if lot + 1e-12 < volume_min:
        if min_risk > allowed + 1e-8:
            return theo, 0.0, min_risk, "minimum lot exceeds risk limit"
        lot = volume_min
    lot = int(lot / volume_step + 1e-12) * volume_step
    lot = min(lot, HARD_MAX_LOT)
    actual = risk_money(tick_size, tick_value, distance, lot)
    if actual > allowed + 1e-8:
        return theo, 0.0, actual, "minimum lot exceeds risk limit"
    return theo, lot, actual, ""


def choose_sl(direction: int, entry: float, raw_sl: float, fib62: float, buffer: float,
              tick_size: float, tick_value: float, allowed: float) -> tuple[float, int]:
    prot = fib62 - buffer if direction == DIR_BUY else fib62 + buffer
    raw_dist = abs(entry - raw_sl)
    prot_dist = abs(entry - prot)
    prot_ok = (direction == DIR_BUY and prot < entry) or (direction == DIR_SELL and prot > entry)
    if not prot_ok:
        return raw_sl, SL_FVG
    maxlot_raw = risk_money(tick_size, tick_value, raw_dist, HARD_MAX_LOT)
    if raw_dist + 1e-12 < prot_dist:
        return prot, SL_FIB62_SMALL
    if maxlot_raw > allowed + 1e-8 and prot_dist + 1e-12 < raw_dist:
        return prot, SL_FIB62_LARGE
    return raw_sl, SL_FVG


def tp_from_rr(direction: int, entry: float, sl: float, rr: float = HARD_TARGET_RR) -> float:
    dist = abs(entry - sl)
    if direction == DIR_BUY:
        return entry + rr * dist
    return entry - rr * dist


def reward_meets_target(entry: float, sl: float, tp: float, target_rr: float = HARD_TARGET_RR) -> tuple[bool, float]:
    risk = abs(entry - sl)
    if risk <= 0:
        return False, 0.0
    actual = abs(tp - entry) / risk
    return actual + 1e-9 >= target_rr, actual


def cooldown_end(start: int, hours: int = 8) -> int:
    return start + max(hours, HARD_MIN_COOLDOWN_H) * 3600


def is_cooldown_active(now: int, end: int) -> bool:
    return end > 0 and now < end


def capital_target_reached(start: float, multiple: float, balance: float, equity: float) -> bool:
    if start <= 0 or multiple <= 0:
        return False
    target = start * multiple
    return balance + 1e-8 >= target or equity + 1e-8 >= target


class CapitalGuard:
    """Persisted 5x lock. Restart does not unlock. Manual reset only."""

    def __init__(self, store: dict | None = None):
        self.store = store if store is not None else {}
        self.start = 0.0
        self.target = 0.0
        self.locked = False

    def init(self, starting_capital: float, balance: float, equity: float, reset: bool = False,
             multiple: float = CAPITAL_MULTIPLE) -> None:
        if reset:
            self.start = balance if balance > 0 else starting_capital
            self.locked = False
        else:
            self.start = float(self.store.get("start", 0.0) or 0.0)
            self.locked = bool(self.store.get("locked", False))
            if self.start <= 0:
                self.start = starting_capital if starting_capital > 0 else balance
        self.target = self.start * multiple
        if not self.locked and capital_target_reached(self.start, multiple, balance, equity):
            self.locked = True
        self._persist()

    def evaluate(self, balance: float, equity: float, multiple: float = CAPITAL_MULTIPLE) -> None:
        if not self.locked and capital_target_reached(self.start, multiple, balance, equity):
            self.locked = True
            self._persist()

    def _persist(self) -> None:
        self.store["start"] = self.start
        self.store["target"] = self.target
        self.store["locked"] = self.locked

    def can_trade(self) -> bool:
        return not self.locked


def process_wait_ticks(setup: dict, ticks: int, new_m15_every: int = 0) -> dict:
    """Waiting-for-retest must not spam entry validation while price is outside."""
    for i in range(ticks):
        new_m15 = new_m15_every > 0 and (i % new_m15_every == 0)
        if setup["state"] != ST_WAITING_RETEST:
            break
        if not new_m15:
            continue
        setup["m15_checks"] = setup.get("m15_checks", 0) + 1
    return setup
