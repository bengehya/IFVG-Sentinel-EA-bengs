# Journal des décisions

Tous les messages utiles commencent par `[IFVG]`.

## Chaîne d’un trade accepté (exemple)

```
[IFVG] HTF Bias: BULLISH
[IFVG] Liquidity detected: SELL-SIDE
[IFVG] Sweep confirmed: SELL-SIDE level=...
[IFVG] SMT confirmed: XAUUSD LL not confirmed by XAGUSD
[IFVG] CISD confirmed: bullish CISD close through opposing open and sweep high
[IFVG] FVG detected: inverted source
[IFVG] FVG inverted: SELL FVG -> BUY IFVG
[IFVG] IFVG created: ...
[IFVG] Waiting for retest
[IFVG] Retest confirmed: count=1
[IFVG] Entry validation: SetupID=...
[IFVG] RR: 1:3.42
[IFVG] Lot: 0.01
[IFVG] Position opened: ticket=... lot=0.01
```

## Refus (exemples imposés par le brief)

```
[IFVG] NO TRADE — SMT missing
[IFVG] NO TRADE — RR insufficient
[IFVG] NO TRADE — 2 positions already open
[IFVG] NO TRADE — 8H cooldown active
[IFVG] NO TRADE — FVG without inversion
[IFVG] NO TRADE — IFVG without retest
[IFVG] NO TRADE — spread too high
[IFVG] NO TRADE — outside configured trading window
[IFVG] NO TRADE — SetupID already executed
[IFVG] NO TRADE — invalid volume
[IFVG] NO TRADE — incorrect filling mode
[IFVG] NO TRADE — insufficient margin
[IFVG] NO TRADE — requotes
[IFVG] NO TRADE — market closed
```

## Cooldown / SL

```
[IFVG] Consecutive SL: 1
[IFVG] Consecutive SL: 2
[IFVG] COOLDOWN MODE: start=... end=...
[IFVG] restored cooldown until ...
[IFVG] Position closed: profit=... LOSS
[IFVG] Consecutive SL: reset to 0 (win)
```

## Audit recommandé

1. Journal MT5 → Experts, filtrer `[IFVG]`.
2. Compter `Position opened` vs `NO TRADE`.
3. Pour chaque ouverture, vérifier que Sweep, SMT (si required), CISD, IFVG, Retest, RR et Lot=0.01 sont présents **avant**.
4. Activer `InpEnableFileLogs` pour un fichier `IFVG_Sentinel_<symbol>_<time>.log` dans `MQL5/Files`.

Un mois avec beaucoup de `NO TRADE` et peu d’ordres est le comportement **attendu**.
