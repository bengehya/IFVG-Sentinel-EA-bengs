#!/usr/bin/env python3
"""Static structure checks for the IFVG Sentinel MQL5 sources."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MQL5 = ROOT / "MQL5"
EA = MQL5 / "Experts" / "IFVG_Sentinel.mq5"
INCLUDE = MQL5 / "Include" / "IFVG"

REQUIRED_MODULES = [
    "Constants.mqh",
    "Types.mqh",
    "Utils.mqh",
    "Safety.mqh",
    "Logger.mqh",
    "Config.mqh",
    "Persistence.mqh",
    "SymbolProvider.mqh",
    "SessionManager.mqh",
    "MarketContext.mqh",
    "PDArray.mqh",
    "LiquidityDetector.mqh",
    "SweepDetector.mqh",
    "SMTDetector.mqh",
    "CISDDetector.mqh",
    "FVGDetector.mqh",
    "IFVGManager.mqh",
    "CooldownManager.mqh",
    "RiskManager.mqh",
    "PositionManager.mqh",
    "TradeManager.mqh",
    "SetupValidator.mqh",
    "EntryEngine.mqh",
    "BacktestStats.mqh",
    "StateMachine.mqh",
    "Dashboard.mqh",
    "SafetySelfTest.mqh",
]

FORBIDDEN = [
    r"martingale",
    r"lot\s*\*\s*2",
    r"recovery\s*trade",
    r"grid\s*trading",
    r"averaging\s+down",
]

REQUIRED_SNIPPETS = {
    EA: [
        "IFVG_SENTINEL_MAGIC",
        "InpMaxLot",
        "InpTargetRR",
        "InpMaxPositions",
        "InpConsecutiveSLLimit",
        "InpCooldownHours",
        "InpGoldOnlyMode",
        "OnTradeTransaction",
        "OnTester",
    ],
    INCLUDE / "Safety.mqh": [
        "IFVG_HARD_MAX_LOT",
        "ClampLotHardCap",
        "CanOpenNewPosition",
        "ShouldEnterCooldown",
        "CooldownEndFromStart",
        "AllowsOrderOnSymbol",
        "RiskMoneyFromDistance",
        "RewardMeetsTarget",
    ],
    INCLUDE / "StateMachine.mqh": [
        "NotifyManagedPositionClosed",
        "cooldown expired → IDLE",
        "position closed → IDLE",
        "CISD not confirmed",
        "DISPLACEMENT FAIL",
        "INVERSION FAIL",
        "InvalidateExpiredIFVG",
        "ExpireActiveSetupIfNeeded",
        "EXPIRED — SetupID=",
        "INVALIDATE — reason=IFVG_VALIDITY_EXPIRED",
        "CLEAR ACTIVE SETUP",
        "IDLE — waiting for new setup",
    ],
    INCLUDE / "IFVGManager.mqh": [
        "ValidityElapsed",
        "MarkExpired",
        "ifvg_validity_seconds",
        "IFVG validity period elapsed",
    ],
    INCLUDE / "EntryEngine.mqh": [
        "ValidityElapsed",
        "Entry validation",
    ],
    INCLUDE / "SMTDetector.mqh": [
        "SKIPPED_GOLD_ONLY",
        "IsGoldOnly",
    ],
    INCLUDE / "Constants.mqh": [
        "#define IFVG_HARD_MAX_LOT            0.01",
        "#define IFVG_HARD_MAX_POSITIONS      2",
        "#define IFVG_HARD_MIN_CONSEC_SL      2",
        "#define IFVG_HARD_MIN_COOLDOWN_H     8",
    ],
}


def brace_balance(text: str, path: Path) -> list[str]:
    errors = []
    s, p, b = 0, 0, 0
    in_str = False
    in_char = False
    in_line = False
    in_block = False
    i = 0
    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""
        if in_line:
            if c == "\n":
                in_line = False
            i += 1
            continue
        if in_block:
            if c == "*" and n == "/":
                in_block = False
                i += 2
                continue
            i += 1
            continue
        if in_str:
            if c == "\\" and n:
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if in_char:
            if c == "\\" and n:
                i += 2
                continue
            if c == "'":
                in_char = False
            i += 1
            continue
        if c == "/" and n == "/":
            in_line = True
            i += 2
            continue
        if c == "/" and n == "*":
            in_block = True
            i += 2
            continue
        if c == '"':
            in_str = True
            i += 1
            continue
        if c == "'":
            in_char = True
            i += 1
            continue
        if c == "{":
            s += 1
        elif c == "}":
            s -= 1
            if s < 0:
                errors.append(f"{path}: unmatched }}")
                return errors
        elif c == "(":
            p += 1
        elif c == ")":
            p -= 1
            if p < 0:
                errors.append(f"{path}: unmatched )")
                return errors
        elif c == "[":
            b += 1
        elif c == "]":
            b -= 1
            if b < 0:
                errors.append(f"{path}: unmatched ]")
                return errors
        i += 1
    if s:
        errors.append(f"{path}: brace imbalance {{}} = {s}")
    if p:
        errors.append(f"{path}: paren imbalance = {p}")
    if b:
        errors.append(f"{path}: bracket imbalance = {b}")
    return errors


def resolve_includes(path: Path, text: str) -> list[str]:
    errors = []
    for m in re.finditer(r'#include\s+[<"]([^>"]+)[>"]', text):
        inc = m.group(1)
        if inc.startswith("Trade/") or inc.startswith("stdlib"):
            continue
        if inc.startswith("IFVG/"):
            target = MQL5 / "Include" / inc
        else:
            target = path.parent / inc
        if not target.exists():
            errors.append(f"{path.name}: missing include {inc} -> {target}")
    return errors


def run() -> int:
    errors: list[str] = []
    if not EA.exists():
        errors.append(f"missing EA {EA}")

    for name in REQUIRED_MODULES:
        p = INCLUDE / name
        if not p.exists():
            errors.append(f"missing module {name}")

    sources = [EA] + sorted(INCLUDE.glob("*.mqh"))
    for src in sources:
        text = src.read_text(encoding="utf-8")
        errors.extend(brace_balance(text, src))
        errors.extend(resolve_includes(src, text))
        lower = text.lower()
        for pat in FORBIDDEN:
            if re.search(pat, lower):
                errors.append(f"{src.name}: forbidden pattern {pat}")

    for path, snippets in REQUIRED_SNIPPETS.items():
        text = path.read_text(encoding="utf-8") if path.exists() else ""
        for snip in snippets:
            if snip not in text:
                errors.append(f"{path.name}: missing required snippet `{snip}`")

    ea_text = EA.read_text(encoding="utf-8") if EA.exists() else ""
    if "DetectCISD" not in (INCLUDE / "CISDDetector.mqh").read_text(encoding="utf-8"):
        errors.append("DetectCISD() missing")
    if "IsValidIFVGRetest" not in (INCLUDE / "IFVGManager.mqh").read_text(encoding="utf-8"):
        errors.append("IsValidIFVGRetest() missing")
    if "MathMin(lot, ClampLotInput" not in (INCLUDE / "Safety.mqh").read_text(encoding="utf-8"):
        if "ClampLotHardCap(lot)" not in (INCLUDE / "Safety.mqh").read_text(encoding="utf-8"):
            errors.append("FinalLot hard cap chain missing")

    if "PositionsTotal" not in (INCLUDE / "PositionManager.mqh").read_text(encoding="utf-8"):
        errors.append("PositionManager does not scan PositionsTotal")

    if "GlobalVariableSet" not in (INCLUDE / "Persistence.mqh").read_text(encoding="utf-8"):
        errors.append("cooldown persistence missing Global Variables")

    if "RiskMoneyFromDistance" not in (INCLUDE / "Safety.mqh").read_text(encoding="utf-8"):
        errors.append("RiskMoneyFromDistance missing")

    if "volume * spec.tick_value" in ea_text and "RiskMoneyFromDistance" not in ea_text:
        errors.append("old risk_money = volume * tick_value reporting formula still used")

    sm_text = (INCLUDE / "StateMachine.mqh").read_text(encoding="utf-8")
    if "void Process(const bool cooldown_active, const int open_positions)" not in sm_text:
        errors.append("StateMachine::Process must take open_positions to unstick after close")
    if "StageWindowExpired" not in sm_text:
        errors.append("CISD/Displacement/FVG definitive-fail window missing")
    if "ExpireActiveSetupIfNeeded" not in sm_text:
        errors.append("expired IFVG must be checked before Entry validation")
    if "InvalidateExpiredIFVG" not in sm_text:
        errors.append("expired IFVG must invalidate and return IDLE")
    ee_text = (INCLUDE / "EntryEngine.mqh").read_text(encoding="utf-8")
    ev_idx = ee_text.find('Decision("Entry validation"')
    elapsed_idx = ee_text.find("ValidityElapsed")
    if ev_idx < 0 or elapsed_idx < 0 or elapsed_idx > ev_idx:
        errors.append("TryEnter must reject expired IFVG before logging Entry validation")
    ev_state = sm_text.find("if(m_setup.state == ST_ENTRY_VALIDATION)")
    if ev_state < 0:
        errors.append("ST_ENTRY_VALIDATION block missing")
    else:
        ev_body = sm_text[ev_state:ev_state + 1600]
        if "ExpireActiveSetupIfNeeded" not in ev_body:
            errors.append("ST_ENTRY_VALIDATION must expire the setup before TryEnter")
        if 'StringFind(m_setup.last_reject, "validity period elapsed")' not in ev_body:
            errors.append("ST_ENTRY_VALIDATION must invalidate on IFVG validity period elapsed")
        if "InvalidateExpiredIFVG" not in ev_body:
            errors.append("ST_ENTRY_VALIDATION elapsed reject must call InvalidateExpiredIFVG")
        try_idx = ev_body.find("TryEnter")
        exp_idx = ev_body.find("ExpireActiveSetupIfNeeded")
        if try_idx < 0 or exp_idx < 0 or exp_idx > try_idx:
            errors.append("ExpireActiveSetupIfNeeded must run before TryEnter in ENTRY_VALIDATION")
    if "g_sm.Process(cd, g_pos.CountOpen())" not in ea_text:
        errors.append("OnTick must pass open position count into Process")
    if "NotifyManagedPositionClosed" not in ea_text:
        errors.append("OnTick/OnTradeTransaction must notify SM on close")

    print(f"checked {len(sources)} MQL5 sources")
    if errors:
        print("STRUCTURE ERRORS:")
        for e in errors:
            print(" -", e)
        return 1
    print("STRUCTURE OK")
    print("modules:", ", ".join(REQUIRED_MODULES))
    print("EA:", EA.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
