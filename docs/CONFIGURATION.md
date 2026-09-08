# Guide de configuration

## Principe

Les inputs existent pour adapter le broker et les timeframes. Ils ne permettent **pas** d’affaiblir les plafonds de sécurité.

| Input | Si vous mettez | Le code applique |
|---|---|---|
| `InpMaxLot = 0.10` | 0.10 | **0.01** |
| `InpMaxPositions = 5` | 5 | **2** |
| `InpConsecutiveSLLimit = 1` | 1 | **2** |
| `InpCooldownHours = 2` | 2 | **8** |
| `InpTargetRR = 2.0` | 2.0 | **3.0** (clamp config + refus OnInit si < 3) |

## Profil recommandé petits comptes (Deriv gold)

```
Symbol                  = XAUUSD          (ou le nom exact Deriv)
HTF                     = H4
Confirmation            = M15
Entry                   = M1
UseSMTFilter            = true
SMTMode                 = SMT_REQUIRED
MaxLot                  = 0.01
TargetRR                = 3.0
MaxPositions            = 2
ConsecutiveSLLimit      = 2
CooldownHours           = 8
MaxSpreadPoints         = 80              (ajuster après observation du spread gold Deriv)
Session timezone        = TZ_UTC
UtcOffsetHours          = <server - UTC>  (mesurer, ne pas inventer)
TradeLondon             = true
TradeNewYork            = true
TradeAsian              = false
MagicNumber             = 26090817
EnableDashboard         = true
EnableLogs              = true
RunSafetySelfTest       = true
```

Pour tester RR 1:4, **ne changez que** `InpTargetRR = 4.0` et relancez un backtest **séparé**.

## Timeframes

Tous les TF sont des inputs. Le cœur (confluence + state machine) ne contient pas de `PERIOD_H4` hard-codé pour la logique métier.

| Rôle | Input | Défaut |
|---|---|---|
| Biais / structure | `InpHTF_Timeframe` | H4 |
| PD Array, liquidité, sweep, FVG, CISD | `InpConfirmation_Timeframe` | M15 |
| Retest / précision d’entrée | `InpEntry_Timeframe` | M1 |

## Timezone — règle

**Aucune heure de session n’est hard-codée sans timezone documenté.**

- `InpSessionTimezone = TZ_SERVER` : les heures d’input sont l’horloge du serveur MT5.
- `TZ_UTC` / `TZ_LONDON` / `TZ_NY` / `TZ_ASIAN` : conversion via `InpUtcOffsetHours` où **server = UTC + offset**.
- **Pas de DST automatique.** Si Londres passe à UTC+1, ajuster l’input. Le robot ne « devine » pas.

Les fenêtres nommées London / NY / Asian sont évaluées en **UTC** (sans DST) :

- Asian : 00:00–08:00 UTC
- London : 07:00–16:00 UTC
- New York : 12:00–21:00 UTC

## SMT

`InpUseSMTFilter = false` désactive le SMT (équivalent `SMT_DISABLED`).

Sinon `InpSMTMode` :

- `SMT_REQUIRED` (défaut) — pas de SMT = pas de trade
- `SMT_OPTIONAL` — le SMT confirme s’il est là, n’bloque pas s’il est absent
- `SMT_DISABLED` — ignoré

## Ce qu’il ne faut jamais faire

- Augmenter le lot après une perte
- Désactiver le cooldown « pour voir plus de trades »
- Passer `TargetRR` sous 3 « pour que ça trade »
- Enlever le SMT obligatoire uniquement pour augmenter la fréquence
- Attacher l’EA sur un compte réel avant backtest + demo + forward test
