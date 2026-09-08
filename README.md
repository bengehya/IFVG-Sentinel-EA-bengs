# IFVG Sentinel EA

Expert Advisor MetaTrader 5 pour **Deriv**, dédié à **XAUUSD / GOLD**.

> **IFVG SENTINEL DOES NOT TRADE BECAUSE IT CAN.**
> **IFVG SENTINEL TRADES ONLY BECAUSE THE COMPLETE STRATEGY SAYS TO TRADE.**

Discipline > fréquence > profit.

## Ce que le robot fait

Il exécute mécaniquement la chaîne IFVG :

HTF Context → PD Array → Liquidity → Sweep → SMT → CISD → Displacement → FVG → Inversion → IFVG → Retest → Entry → SL / TP

Une condition isolée **ne déclenche jamais** une entrée. Si une condition obligatoire manque : **NO TRADE**.

## Protections non négociables

| Règle | Plafond code |
|---|---|
| Lot maximum | **0.01** (hard-coded, `MathMin(..., 0.01)`) |
| Positions simultanées | **2** |
| Après 2 SL consécutifs | **cooldown 8 heures** (persistant via Global Variables) |
| Martingale / grid / averaging | **interdit** — aucune logique de ce type |
| R:R minimum | **1:3** (ou 1:4 via `TargetRR`) |

Même si l’input `MaxLot` est mis à `0.10`, le lot final reste `0.01`.

## Arborescence

```
MQL5/
  Experts/IFVG_Sentinel.mq5
  Include/IFVG/*.mqh
docs/
tests/
```

## Installation rapide

Voir [docs/INSTALL_DERIV.md](docs/INSTALL_DERIV.md).

Copier :

- `MQL5/Experts/IFVG_Sentinel.mq5` → `MQL5/Experts/`
- `MQL5/Include/IFVG/` → `MQL5/Include/IFVG/`

Compiler dans MetaEditor (`F7`). Attacher sur **XAUUSD** (ou le symbole Deriv équivalent).

## Documentation

| Document | Contenu |
|---|---|
| [docs/ALGORITHMIC_RULES.md](docs/ALGORITHMIC_RULES.md) | Traduction mesurable de chaque concept |
| [docs/AMBIGUOUS_RULES.md](docs/AMBIGUOUS_RULES.md) | Interprétations explicites (pas de subjectivité silencieuse) |
| [docs/PARAMETERS.md](docs/PARAMETERS.md) | Liste des inputs |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | Guide de configuration |
| [docs/BACKTESTING.md](docs/BACKTESTING.md) | Config A (RR=3) vs Config B (RR=4) |
| [docs/INSTALL_DERIV.md](docs/INSTALL_DERIV.md) | Installation Deriv MT5 |
| [docs/DECISION_JOURNAL.md](docs/DECISION_JOURNAL.md) | Format des logs |
| [docs/TEST_REPORT.md](docs/TEST_REPORT.md) | Rapport des tests de sécurité |

## Tests locaux (sans MetaEditor)

```bash
python3 tests/test_safety_rules.py
python3 tests/test_mql5_structure.py
```

Ces tests valident les plafonds (lot, positions, cooldown, confluence, R:R). La compilation `.ex5` doit être faite dans MetaEditor sur Windows / le terminal Deriv.

## Avant le réel

**BACKTEST → DEMO Deriv → FORWARD TEST → seulement ensuite REAL ACCOUNT.**
