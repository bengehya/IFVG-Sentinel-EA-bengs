# Rapport de tests

Date : 2026-09-08  
Branche : `cursor/ifvg-sentinel-ea-2372`  
EA : `MQL5/Experts/IFVG_Sentinel.mq5` v1.0.0

## Environnement

| Élément | Statut |
|---|---|
| Structure MQL5 (includes, braces, modules) | Exécuté via `tests/test_mql5_structure.py` |
| Tests de sécurité 1–10 (miroir Python = logique `CIFVGSafety` / `CSetupValidator`) | Exécuté via `tests/test_safety_rules.py` |
| Self-test embarqué `CIFVGSafetySelfTest::Run` | Compilé dans l’EA, lancé à `OnInit` si `InpRunSafetySelfTest=true` |
| Compilation MetaEditor (`F7`) | **Non exécutable ici** (pas de MetaEditor / metaeditor64 sur cet environnement Linux) |
| Strategy Tester MT5 | À lancer sur le terminal Deriv |
| Demo Deriv + redémarrage terminal | À lancer par l’utilisateur avant tout compte réel |

La compilation `.ex5` **doit** être faite localement. Les tests Python verrouillent la politique de sécurité mais ne remplacent pas `F7`.

## TEST 1–10 (obligatoires)

| # | Scénario | Attendu | Résultat logique |
|---|---|---|---|
| 1 | Lot calculé = 0.05 | 0.01 maximum | PASS (`ClampLotHardCap`) |
| 2 | 2 positions ouvertes | NO NEW TRADE | PASS |
| 3 | 1 position ouverte | 2ᵉ setup possible si confluence OK | PASS |
| 4 | 2 SL consécutifs | cooldown 8h | PASS |
| 5 | Setup parfait pendant cooldown | NO TRADE | PASS |
| 6 | FVG sans inversion | NO TRADE | PASS |
| 7 | IFVG sans retest | NO TRADE | PASS |
| 8 | Sweep sans SMT (SMT required) | NO TRADE | PASS |
| 9 | RR 1:2.4 vs TargetRR=3 | NO TRADE | PASS |
| 10 | RR 1:3.2 vs TargetRR=3 | RR gate OK (le reste de la confluence s’applique encore) | PASS |

Extras : input `MaxLot=0.10` → 0.01 ; `MaxPositions=99` → 2 ; `CooldownHours=4` → 8 ; win reset `ConsecutiveSL=0`.

## Protections vérifiées dans le source

- [x] `IFVG_HARD_MAX_LOT 0.01` + `ClampLotHardCap` avant chaque volume
- [x] `IFVG_HARD_MAX_POSITIONS 2` même si l’input demande plus
- [x] cooldown persisté (`GlobalVariableSet` / `Get`)
- [x] Magic Number isolé (`PositionGetInteger(POSITION_MAGIC)`)
- [x] `DetectCISD()` dédié
- [x] `IsValidIFVGRetest()` dédié
- [x] aucune occurrence martingale / lot×2 / grid / averaging down
- [x] filling mode détecté (IOC / FOK / RETURN)
- [x] dashboard + logs `[IFVG]`

## Checklist §45 (état)

| Item | État |
|---|---|
| XAUUSD configurable / specs broker auto | Code OK — runtime Deriv à confirmer |
| Compatible MT5 | Source MQL5 modulaire — **compiler dans MetaEditor** |
| Compatible Deriv | Detection symbol + filling + volume_min>0.01 = init fail |
| IFVG / liquidité / sweep / SMT / CISD | Modules dédiés + règles mesurables documentées |
| Retest obligatoire | Gate Entry Engine + TEST 7 |
| RR 1:3 et 1:4 | `TargetRR` input, stats non mélangées |
| Max 0.01 lot / max 2 positions | Hard-coded |
| 2 SL → 8h cooldown, aucun trade pendant | Hard-coded + persisté |
| Pas de martingale / revenge | Pas de branche lot↑ après perte |
| Magic / dashboard / logs / backtest report | Implémentés |
| Tests de sécurité | Python + self-test OnInit |
| Code propre et modulaire | `Include/IFVG/*.mqh` |

## Forward test (à faire sur Deriv DEMO)

1. Compiler sans erreur.
2. Tester Strategy Tester, plusieurs périodes, Config A puis Config B.
3. Compte demo : logs, lot 0.01, max 2 positions.
4. Simuler 2 SL → vérifier cooldown 8h.
5. Setup pendant cooldown → aucun ordre.
6. Redémarrer MT5 → cooldown toujours actif (Global Variables).

**BACKTEST → DEMO → FORWARD TEST → seulement ensuite REAL ACCOUNT.**
