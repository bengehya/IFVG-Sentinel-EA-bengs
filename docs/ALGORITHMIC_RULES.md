# Règles algorithmiques (mesurables)

Ce document est la traduction **objective** de la stratégie IFVG. Aucune règle du type « le marché a l’air haussier » n’est utilisée dans le code.

## Machine à états

```
IDLE
 → HTF_ANALYSIS
 → LIQUIDITY_DETECTED
 → SWEEP_DETECTED
 → SMT_VALIDATED
 → CISD_VALIDATED
 → FVG_DETECTED
 → IFVG_CREATED
 → WAITING_RETEST
 → RETEST_DETECTED
 → ENTRY_VALIDATION
 → ORDER_SENT
 → POSITION_ACTIVE
 → POSITION_CLOSED
 → IDLE

Toute invalidation critique → SETUP_INVALIDATED → IDLE
Cooldown 8h → ST_COOLDOWN / EA_COOLDOWN (aucun ordre)
```

Les états avant `WAITING_RETEST` ne progressent que sur **nouvelle bougie** du timeframe de confirmation. Le retest est évalué à chaque tick / nouvelle bougie M1.

## 1. HTF bias

**Timeframe :** `InpHTF_Timeframe` (défaut H4).

**Swings :** un swing high à l’index `i` est confirmé si `high[i]` est strictement supérieur aux `swing_left` barres plus anciennes et supérieur ou égal aux `swing_right` barres plus récentes (fractal borné). Inverse pour swing low.

**Biais :**

| Condition | Biais |
|---|---|
| dernier swing high > précédent **et** dernier swing low > précédent | BULLISH |
| dernier swing high < précédent **et** dernier swing low < précédent | BEARISH |
| sinon, ou moins de 2 highs **et** 2 lows confirmés | NEUTRAL → **pas de trade** |

Invalidation : un biais NEUTRAL ou un mismatch direction / biais bloque l’Entry Engine.

## 2. PD Array

Scanné sur `InpConfirmation_Timeframe` (défaut M15).

### FVG HTF/confirmation

Définition 3 bougies (série `true`, index 0 = bougie courante) :

- FVG haussier : `low[i-1] > high[i+1]`, zone = `[high[i+1], low[i-1]]`
- FVG baissier : `high[i-1] < low[i+1]`, zone = `[high[i-1], low[i+1]]`

### Order Block

Au moins `ob_impulse_bars` bougies consécutives dans la même direction dont la somme des corps ≥ `ATR(14) * ob_displacement_atr`. L’OB est la dernière bougie **opposée** précédant cette impulsion.

Chaque zone stocke : high, low, timeframe, type, direction, timestamp, statut (`ACTIVE` / `INVALIDATED` / `USED` / `EXPIRED`).

**Expiration :** `created + pd_expire_bars * secondes_du_TF`.

**Invalidation :** close sous `low` d’une zone BUY, close au-dessus `high` d’une zone SELL.

Sans zone PD active alignée avec le biais : le setup ne quitte pas l’attente.

## 3. Liquidité

Sur le TF de confirmation.

- **Buy-side (BSL)** : swing highs, equal highs (deux niveaux dans `equal_points`), old extreme (plus haut des ~80 dernières barres).
- **Sell-side (SSL)** : swing lows, equal lows, old extreme.

Un niveau n’est plus « resting » s’il est marqué swept ou si `now - created > liq_expire_bars * secondes_TF`.

Le robot **mémorise** le niveau avant qu’il soit pris (`active && !swept`).

## 4. Sweep (pas un simple dépassement)

Un sweep n’est validé que si **toutes** ces conditions sont vraies sur une bougie **close** après la création du niveau :

### BUY (SSL)

1. `low < level - min_sweep_points`
2. `close > level + min_closeback_points`
3. bougie haussière (`close > open`)
4. rejet : `(close - low) / range ≥ 0.55`
5. `range ≥ ATR(14) * min_sweep_atr_mult`

### SELL (BSL)

1. `high > level + min_sweep_points`
2. `close < level - min_closeback_points`
3. bougie baissière
4. rejet : `(high - close) / range ≥ 0.55`
5. même filtre ATR

Un close au-delà du niveau **sans** retour = break, **pas** un sweep.

Âge max : `sweep_max_age_bars` barres après le niveau.

## 5. SMT (filtre, jamais une entrée)

### Mode Gold-only (`InpGoldOnlyMode = true`, défaut Deriv)

Le robot trade **uniquement** le symbole gold configuré (`InpSymbol`, défaut `XAUUSD`).

- Aucune dépendance à `USDX`, `XAGUSD`, `DXY` ou tout autre marché.
- Aucun `SymbolSelect` sur un symbole externe.
- Statut journal : **`SMT = SKIPPED_GOLD_ONLY`**.
- Ce n’est **pas** une confirmation SMT. Aucun SMT intra-XAUUSD n’est inventé.
- L’absence de USDX/XAGUSD **ne peut pas** invalider un setup gold.

La chaîne obligatoire reste : HTF → PD → Liquidity → Sweep → CISD → Displacement → FVG → Inversion → IFVG → Retest → gates → RR.

### Mode multi-symboles (`InpGoldOnlyMode = false`)

Comparaison des 2 derniers swings confirmés sur le TF de confirmation.

**Corrélation positive (XAU vs XAG) :**

- BUY SMT : gold fait un lower low, l’autre **ne** fait **pas** de lower low
- SELL SMT : gold higher high, l’autre pas de higher high

**Corrélation inverse (XAU vs DXY / USDX) :**

- BUY SMT : gold lower low, l’autre **pas** de higher high
- SELL SMT : gold higher high, l’autre **pas** de lower low

Modes : `DISABLED` / `OPTIONAL` / `REQUIRED`. Symbole absent + SMT required = **NO TRADE**.

Les symboles SMT ne sont **jamais** des instruments tradables. Un ordre hors `InpSymbol` est refusé.

## 5b. Journal de chaîne

Aux transitions (pas à chaque bougie) :

`HTF` / `PD ARRAY` / `LIQUIDITY` / `SWEEP` / `SMT` / `CISD` / `DISPLACEMENT` / `FVG` / `INVERSION` / `IFVG` / `RETEST` / `ENTRY GATES` / `RR` / `FINAL DECISION`

SMT Gold-only = `SKIPPED_GOLD_ONLY`. RR fail inclut actual vs target.

## 6. CISD — `DetectCISD()`

Retour : `direction`, `timestamp`, `confirmation_level`, `valid`, `setup_state`, `body_ratio`, `reason`.

Ce n’est **pas** « une bougie verte ».

Après le sweep :

1. Trouver la bougie de livraison opposée au sweep (bear close pour un BUY, bull close pour un SELL), en partant de la bougie de sweep vers le passé.
2. Sur les `cisd_max_bars_after_sweep` bougies **plus récentes** que le sweep :
   - corps ≥ `ATR * cisd_min_body_atr`
   - `corps / range ≥ 0.5`
   - **BUY :** close haussier **et** `close > open_opposé` **et** `close > high_du_sweep`
   - **SELL :** close baissier **et** `close < open_opposé` **et** `close < low_du_sweep`

## 7. Displacement

Après CISD, somme des corps dans la direction du setup sur `displacement_min_bars` (+2 max) ≥ `ATR * displacement_atr_mult`.

## 8. FVG — module `FVGDetector`

Même définition 3 bougies que le PD Array, avec `fvg_min_points` de taille minimale, barres closes si `fvg_require_closed_bars`.

Cycle : `FVG_CREATED` → `FVG_TESTED` (overlap prix / zone) → `FVG_BROKEN` / `FVG_INVERTED` si un **close** traverse entièrement la zone contre la direction d’origine.

Une FVG non inversée **n’autorise aucun trade**.

## 9. IFVG

Quand une FVG est inversée :

- FVG BUY inversée → IFVG SELL
- FVG SELL inversée → IFVG BUY

Cycle : `CREATED` → `WAITING_FOR_RETEST` → `RETEST` → `ENTRY_VALIDATION` → `TRADED` / `INVALIDATED` / `EXPIRED`.

Durée de vie : `ifvg_validity_seconds` depuis l’inversion.

## 10. Retest — `IsValidIFVGRetest()`

TRUE seulement si :

1. IFVG non tradée / non expirée / non invalidée
2. `now ≤ expire`
3. `retest_count < ifvg_max_retests`
4. la bougie **close** d’entrée intersecte `[low - tolerance, high + tolerance]`
5. BUY : `close ≥ zone_low` ; SELL : `close ≤ zone_high`

Pas d’entrée anticipée : le retest se juge sur la bougie **fermée** du TF d’entrée.

## 11. Entry Engine — 19 portes

Dans l’ordre (une seule échec = NO TRADE) :

1. HTF context valide
2. PD Array actif aligné
3. liquidité identifiée
4. sweep confirmé
5. SMT si obligatoire (**sauf Gold-only** : `SKIPPED_GOLD_ONLY`, pas un blocker)
6. CISD
7. displacement
8. FVG valide
9. IFVG créée
10. retest confirmé
11. direction cohérente
12. spread ≤ `MaxSpreadPoints`
13. session autorisée
14. cooldown terminé
15. positions < 2
16. volume autorisé (≤ 0.01, step, min/max broker)
17. SL valide (structure + stops level)
18. TP valide
19. R:R réel ≥ `TargetRR`

Plus : SetupID unique, filling mode détecté, trading enabled, connexion, prix > 0.

## 12. SL / TP

- BUY SL = `sweep.extreme - sl_buffer_points`
- SELL SL = `sweep.extreme + sl_buffer_points`
- `RiskDistance = |entry - SL|`
- BUY TP = `entry + RiskDistance * TargetRR`
- SELL TP = `entry - RiskDistance * TargetRR`

Si le R:R réel (après normalisation tick) < TargetRR → **NO TRADE**.

## 13. Lot

```
lot = min(calculated, input_max, 0.01)
lot = normalize(volume_step)
si lot < volume_min ou lot > 0.01 → 0 (refus)
```

Aucune formule ne multiplie le lot après une perte.

## 14. Positions

`CountOpen()` ne compte que `magic == IFVG_SENTINEL_MAGIC` **et** le symbole de l’EA. Maximum 2. Pas d’averaging, pas de pyramidage.

## 15. Cooldown

`ConsecutiveSL` : +1 sur DEAL_REASON_SL, reset à 0 sur un trade gagnant (profit > 0).

Si `ConsecutiveSL >= 2` : `CooldownEnd = now + max(input, 8) heures`. Persisté dans les Global Variables. Pendant le cooldown : **aucun ordre**, même setup parfait.

## 16. Magic

Défaut `26090817` (`IFVG_SENTINEL_MAGIC`). L’EA ne ferme / ne modifie aucune position d’un autre magic.
