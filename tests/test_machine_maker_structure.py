#!/usr/bin/env python3
"""Static structure checks for MACHINE MAKER MQL5 sources."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MQL5 = ROOT / "MQL5"
EA = MQL5 / "Experts" / "Machine_Maker.mq5"
INCLUDE = MQL5 / "Include" / "MachineMaker"

REQUIRED_MODULES = [
    "Constants.mqh",
    "Types.mqh",
    "Utils.mqh",
    "Safety.mqh",
    "Logger.mqh",
    "Config.mqh",
    "Persistence.mqh",
    "SymbolProvider.mqh",
    "DirectionEngine.mqh",
    "FibonacciEngine.mqh",
    "FVGEngine.mqh",
    "EntryModels.mqh",
    "CooldownManager.mqh",
    "RiskEngine.mqh",
    "PositionManager.mqh",
    "TradeManager.mqh",
    "BacktestStats.mqh",
    "StateMachine.mqh",
    "Dashboard.mqh",
    "SafetySelfTest.mqh",
]

FORBIDDEN = [
    r"martingale",
    r"lot\s*\*\s*2",
    r"grid\s*trading",
    r"averaging\s+down",
    r"IFVG",
    r"CISD",
    r"SMT",
    r"USDX",
    r"XAGUSD",
]

ALLOWED_IFVG_MENTIONS = {"SafetySelfTest.mqh"}  # none expected

REQUIRED_SNIPPETS = {
    EA: [
        "MACHINE MAKER",
        "InpRiskPercent",
        "InpMaxLot",
        "InpTargetRR",
        "MM_TF_DAILY",
        "MM_IsGoldSymbol",
        "OnTradeTransaction",
        "OnTester",
    ],
    INCLUDE / "Constants.mqh": [
        "#define MM_DEFAULT_RISK_PERCENT      2.0",
        "#define MM_HARD_MAX_POSITIONS        2",
        "#define MM_HARD_MIN_CONSEC_SL        2",
        "#define MM_HARD_MIN_COOLDOWN_H       8",
        "#define MM_HARD_TARGET_RR            4.0",
        "#define MM_TF_DAILY                  PERIOD_D1",
        "#define MM_TF_H4                     PERIOD_H4",
        "#define MM_TF_M15                    PERIOD_M15",
    ],
    INCLUDE / "Safety.mqh": [
        "LotFromAllowedRisk",
        "RiskMoneyFromDistance",
        "AllowedRiskMoney",
        "VolumeRespectsBroker",
        "TheoreticalLotFromRisk",
    ],
    INCLUDE / "StateMachine.mqh": [
        "MM_ST_WAITING_FOR_RETEST",
        "MM_ST_COOLDOWN",
        "full break through FVG",
        "WAITING_FOR_RETEST",
    ],
    INCLUDE / "TradeManager.mqh": [
        "insufficient margin",
        "OrderCheck",
    ],
    INCLUDE / "RiskEngine.mqh": [
        "ACCOUNT_EQUITY",
        "ACCOUNT_CURRENCY",
        "AllowedRisk=",
        "TheoreticalLot=",
        "VolumeMin=",
    ],
    INCLUDE / "Logger.mqh": [
        "[MACHINE MAKER][RISK]",
        "NO TRADE — ",
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
        if inc.startswith("Trade/"):
            continue
        if inc.startswith("MachineMaker/"):
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
        if not (INCLUDE / name).exists():
            errors.append(f"missing module {name}")

    sources = [EA] + sorted(INCLUDE.glob("*.mqh"))
    for src in sources:
        text = src.read_text(encoding="utf-8")
        errors.extend(brace_balance(text, src))
        errors.extend(resolve_includes(src, text))
        lower = text.lower()
        for pat in FORBIDDEN:
            if re.search(pat, text if pat[0].isupper() else lower):
                if pat in ("IFVG", "CISD", "SMT", "USDX", "XAGUSD") and re.search(pat, text):
                    errors.append(f"{src.name}: forbidden leftover `{pat}`")
                elif pat not in ("IFVG", "CISD", "SMT", "USDX", "XAGUSD") and re.search(pat, lower):
                    errors.append(f"{src.name}: forbidden pattern {pat}")

    for path, snippets in REQUIRED_SNIPPETS.items():
        text = path.read_text(encoding="utf-8") if path.exists() else ""
        for snip in snippets:
            if snip not in text:
                errors.append(f"{path.name}: missing `{snip}`")

    utils = (INCLUDE / "Utils.mqh").read_text(encoding="utf-8")
    if "if(tf == PERIOD_CURRENT)" not in utils:
        errors.append("CopyRates must reject PERIOD_CURRENT")
    if "PERIOD_CURRENT: return 0" not in utils.replace(" ", ""):
        if "case PERIOD_CURRENT: return 0" not in utils.replace("\n", " ").replace("  ", " "):
            pass
    ea_text = EA.read_text(encoding="utf-8") if EA.exists() else ""
    if "InpTargetRR            = 4.0" not in ea_text:
        errors.append("default RR must be 1:4")
    if "InpRiskPercent         = 2.0" not in ea_text:
        errors.append("default InpRiskPercent must be 2.0")
    if "InpStartingCapital" in ea_text or "InpRiskMoney" in ea_text:
        errors.append("fixed $50 / $10 capital inputs must not remain")
    if "InpMaxLot              = 0.0" not in ea_text:
        errors.append("InpMaxLot default must be 0 (broker max only)")
    trade = (INCLUDE / "TradeManager.mqh").read_text(encoding="utf-8")
    if "MarginIsSufficient" in trade:
        errors.append("margin must not be a strategy filter")
    if "OrderCheck" not in trade:
        errors.append("TradeManager must OrderCheck before send")
    sm = (INCLUDE / "StateMachine.mqh").read_text(encoding="utf-8")
    if "WITHDRAWAL_REQUIRED" in sm or "CapitalGuard" in sm:
        errors.append("StateMachine must not lock trading on capital multiple")
    if "m_cd.Active(now)" not in sm or "MM_ST_COOLDOWN" not in sm:
        errors.append("consecutive-SL cooldown must remain in StateMachine")
    safety = (INCLUDE / "Safety.mqh").read_text(encoding="utf-8")
    if "ClampLotHardCap" in safety or "MM_HARD_MAX_LOT" in safety:
        errors.append("strategic 0.01 lot hard cap must not remain")
    if (INCLUDE / "CapitalGuard.mqh").exists():
        errors.append("CapitalGuard.mqh must be removed")
    for src in sources:
        text = src.read_text(encoding="utf-8")
        if "USC" in text or re.search(r"USD\s*\*\s*100", text):
            errors.append(f"{src.name}: hardcoded USD/USC conversion is forbidden")
        if src.name == "Utils.mqh":
            continue
        if re.search(r"\b_Period\b", text) or re.search(r"\bPeriod\s*\(", text):
            errors.append(f"{src.name}: must not read chart/tester Period()")

    old_ea = MQL5 / "Experts" / "IFVG_Sentinel.mq5"
    if not old_ea.exists():
        errors.append("old IFVG EA must remain in the tree for history comparison")

    print(f"checked {len(sources)} MACHINE MAKER sources")
    if errors:
        print("STRUCTURE ERRORS:")
        for e in errors:
            print(" -", e)
        return 1
    print("STRUCTURE OK")
    print("modules:", ", ".join(REQUIRED_MODULES))
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
