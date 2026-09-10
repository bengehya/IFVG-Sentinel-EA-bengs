# MACHINE MAKER

Expert Advisor MetaTrader 5 for **Deriv**, **XAUUSD / GOLD** only.

This repository still contains the previous **IFVG Sentinel** sources (`MQL5/Experts/IFVG_Sentinel.mq5`, `MQL5/Include/IFVG/`) so that implementation can be compared and recovered from Git history. **The live product is MACHINE MAKER.**

> MACHINE MAKER does not trade because it can.
> It trades only when Daily + H4 agree, an M15 FVG sits on the correct side of 50%, and one of the two entry models confirms on a closed candle.

## Strategy

```
Daily direction → H4 confirmation → M15 FVG in discount/premium
→ Model 1 (wick into FVG + close outside) or Model 2 (FVG 50% + close back)
→ Structural SL (FVG or Fib 0.62) → TP at 1:4
```

No SMT, no IFVG conversion, no CISD, no liquidity sweep, no order blocks.

## Safety

| Rule | Code floor |
|---|---|
| Gold only | XAU / GOLD in the symbol name |
| Max lot | **0.01** |
| Max positions | **2** |
| 2 consecutive SL | **8 hour cooldown** (persisted) |
| Starting capital × 5 | **WITHDRAWAL_REQUIRED** until manual reset |
| Martingale / grid / averaging | forbidden |
| Target RR | **1:4** |
| Chart/tester TF | ignored — internals are D1 / H4 / M15 |

Small-capital default: `InpStartingCapital=50`, `InpRiskMoney=10`.

## Tree

```
MQL5/
  Experts/Machine_Maker.mq5          ← current EA
  Experts/IFVG_Sentinel.mq5          ← previous strategy (kept)
  Include/MachineMaker/*.mqh
  Include/IFVG/*.mqh                 ← previous strategy (kept)
docs/MACHINE_MAKER_RULES.md
tests/test_machine_maker.py
tests/test_machine_maker_structure.py
```

## Install

Copy `MQL5/Experts/Machine_Maker.mq5` and `MQL5/Include/MachineMaker/` into the Deriv MT5 data folder. Compile with MetaEditor (F7). Attach to **XAUUSD**. Tester timeframe may be M1/M5/M15/H1; strategy TFs stay D1/H4/M15.

## Tests

```bash
python3 tests/test_machine_maker.py
python3 tests/test_machine_maker_structure.py
python3 tests/test_safety_rules.py
python3 tests/test_mql5_structure.py
```

Deterministic interpretations: [docs/MACHINE_MAKER_RULES.md](docs/MACHINE_MAKER_RULES.md).

**BACKTEST → DEMO → FORWARD TEST → only then a real account.**
