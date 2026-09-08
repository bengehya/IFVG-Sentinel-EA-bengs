# Scénarios de validation (Strategy Tester / demo)

Utiliser ces scénarios après compilation MetaEditor. Les tests Python couvrent déjà la **politique** (lot, positions, cooldown, confluence). Le tester couvre l’**exécution** broker.

## Préparation

- `InpRunSafetySelfTest = true` → le journal OnInit doit lister TEST 1–10 PASS.
- `InpEnableLogs = true`
- `InpDebugMode = true` pour la première passe.

## S1 — Lot

Forcer mentalement un calcul 0.05 : le journal doit montrer `Lot: 0.01`. Le volume des positions dans l’historique = 0.01 uniquement.

## S2 — Deux positions

Ouvrir (ou attendre) 2 positions magic IFVG. Un nouveau setup parfait doit logger `NO TRADE — 2 positions already open`.

## S3 — Une position

Avec 1 position, un **nouveau SetupID** (autre sweep/IFVG) peut passer si toute la confluence est vraie. Pas d’ajout sur le même SetupID.

## S4 — Deux SL

Fermer 2 positions au SL. Journal :

```
[IFVG] Consecutive SL: 2
[IFVG] COOLDOWN MODE: ...
```

`Cooldown remaining` dashboard > 0.

## S5 — Setup pendant cooldown

Ne pas désactiver le cooldown. Aucun `Position opened` jusqu’à `Cooldown remaining: 0`.

## S6 — FVG seule

Sur un graphe avec FVG non inversée : pas d’ordre. Log `NO TRADE` / état bloqué à FVG_DETECTED.

## S7 — IFVG sans retest

IFVG créée, prix qui n’est pas revenu dans la zone : pas d’ordre (`Waiting for retest`).

## S8 — SMT required

Retirer / invalider le symbole SMT. `NO TRADE — SMT missing`.

## S9 — RR insuffisant

Réduire artificiellement le TP potentiel (ex. sweep trop loin vs structure) : `NO TRADE — RR insufficient` si réel < TargetRR.

## S10 — RR 1:3.2

Sweep assez proche pour RR ≥ 3, confluence complète : ordre autorisé, volume 0.01.

## Persistence redémarrage

1. Entrer en cooldown.
2. Noter `CD_END` (Global Variables du terminal).
3. Fermer MT5, rouvrir, rattacher l’EA.
4. Journal : `restored cooldown until ...`
5. Toujours aucun trade.

## Config A vs B

Deux passes tester **séparées** : `TargetRR=3` puis `TargetRR=4`. Ne pas agréger les rapports.
