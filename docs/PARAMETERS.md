# Paramètres (inputs)

Les plafonds de sécurité du tableau du bas **gagnent toujours** contre l’input.

## STRATEGY

| Input | Défaut | Rôle |
|---|---|---|
| `InpSymbol` | XAUUSD | Instrument. Chaîne vide / `current` → `_Symbol` |
| `InpGoldOnlyMode` | true | XAUUSD-only : pas de SMT externe obligatoire, aucun ordre hors symbole |
| `InpHTF_Timeframe` | H4 | Biais structurel |
| `InpConfirmation_Timeframe` | M15 | PD, liquidité, sweep, CISD, FVG |
| `InpEntry_Timeframe` | M1 | Retest |
| `InpAllowBuy` / `InpAllowSell` | true | Coupe une direction |

## SMT

| Input | Défaut | Rôle |
|---|---|---|
| `InpUseSMTFilter` | true | Master switch |
| `InpSMTMode` | SMT_REQUIRED | required / optional / disabled |
| `InpSMTSymbol1` | XAGUSD | Corrélé #1 |
| `InpSMTCorr1` | CORR_POSITIVE | Signe de corrélation |
| `InpSMTSymbol2` | USDX | Corrélé #2 (DXY-like) |
| `InpSMTCorr2` | CORR_INVERSE | Signe |
| `InpSMTLookback` | 80 | Barres de swings SMT |
| `InpSMTSwingLeft` / `Right` | 2 | Fractal SMT |

## RISK

| Input | Défaut | Plafond code |
|---|---|---|
| `InpMaxLot` | 0.01 | `min(input, 0.01)` |
| `InpTargetRR` | 3.0 | minimum effectif 3.0 |
| `InpMaxPositions` | 2 | `min(input, 2)` |
| `InpSLBufferPoints` | 50 | marge au-delà du sweep |
| `InpMinSLPoints` | 100 | distance SL minimale |

## COOLDOWN

| Input | Défaut | Plafond code |
|---|---|---|
| `InpConsecutiveSLLimit` | 2 | `max(input, 2)` |
| `InpCooldownHours` | 8 | `max(input, 8)` |

## MARKET FILTER

| Input | Défaut | Notes timezone |
|---|---|---|
| `InpMaxSpreadPoints` | 80 | points du symbole (pas pips génériques) |
| `InpTradingSessionStartHour/Minute` | 7:00 | interprétés selon `InpSessionTimezone` |
| `InpTradingSessionEndHour/Minute` | 21:00 | fenêtre wrap possible (ex. 22→06) |
| `InpSessionTimezone` | TZ_UTC | SERVER / UTC / LONDON / NY / ASIAN |
| `InpUtcOffsetHours` | 0 | **server = UTC + offset** |
| `InpTradeLondon/NewYork/Asian` | T/T/F | fenêtres UTC documentées, **pas de DST auto** |

## STRUCTURE / SWEEP

| Input | Défaut | Rôle |
|---|---|---|
| `InpSwingLeft` / `Right` | 2 | fractal liquidité / HTF |
| `InpHTFStructureLookback` | 80 | barres H4 |
| `InpEqualPoints` | 80 | equal high/low |
| `InpLiqExpireBars` | 80 | TTL liquidité |
| `InpMinSweepPoints` | 20 | wick beyond |
| `InpMinSweepClosebackPoints` | 5 | close back |
| `InpMinSweepATRMult` | 0.6 | range min |
| `InpSweepMaxAgeBars` | 12 | âge sweep |
| `InpPDExpireBars` | 60 | TTL PD |
| `InpOBDisplacementATR` | 1.2 | OB impulse |
| `InpOBImpulseBars` | 3 | nb bougies impulse |

## CISD / DISPLACEMENT

| Input | Défaut |
|---|---|
| `InpCISDMinBodyATR` | 0.4 |
| `InpCISDMaxBarsAfterSweep` | 8 |
| `InpDisplacementATRMult` | 1.0 |
| `InpDisplacementMinBars` | 1 |

## IFVG

| Input | Défaut |
|---|---|
| `InpFVGMinPoints` | 20 |
| `InpFVGMaxAgeBars` | 40 |
| `InpFVGRequireClosedBars` | true |
| `InpIFVG_Tolerance` | 30 |
| `InpIFVG_MaxRetests` | 2 |
| `InpIFVG_ValidityPeriod` | 14400 s (4h) |
| `InpIFVGRequireCloseThrough` | true |

## SYSTEM

| Input | Défaut |
|---|---|
| `InpMagicNumber` | 26090817 (`IFVG_SENTINEL_MAGIC`) |
| `InpEnableDashboard` | true (off dans le tester) |
| `InpEnableLogs` | true |
| `InpEnableFileLogs` | false (fichier dans `MQL5/Files`) |
| `InpDebugMode` | false |
| `InpRunSafetySelfTest` | true — OnInit FAIL si un test interne casse |

## Constantes non exposées

```
IFVG_HARD_MAX_LOT         = 0.01
IFVG_HARD_MAX_POSITIONS   = 2
IFVG_HARD_MIN_CONSEC_SL   = 2
IFVG_HARD_MIN_COOLDOWN_H  = 8
IFVG_SENTINEL_MAGIC       = 26090817
```
