# Installation — Deriv MetaTrader 5

## 1. Installer Deriv MT5

1. Créer un compte **demo** Deriv (jamais un compte réel en premier).
2. Télécharger MetaTrader 5 depuis le site Deriv.
3. Se connecter au serveur demo Deriv.

## 2. Copier les fichiers

Dans le terminal MT5 : `Fichier → Ouvrir le dossier de données`.

Copier depuis ce dépôt :

```
MQL5/Experts/IFVG_Sentinel.mq5     →  <data>/MQL5/Experts/IFVG_Sentinel.mq5
MQL5/Include/IFVG/*                →  <data>/MQL5/Include/IFVG/
```

Le dossier `Include/IFVG/` doit exister **intégralement**. Les `#include <IFVG/...>` échouent sinon.

## 3. Compiler

1. Ouvrir `IFVG_Sentinel.mq5` dans MetaEditor (`F4` depuis MT5).
2. Appuyer sur `F7`.
3. La compilation doit produire `IFVG_Sentinel.ex5` **sans erreur**.

Les warnings éventuels liés à des conversions numériques doivent être relus, pas ignorés.

## 4. Propriétés du symbole (jamais supposer)

Le robot lit tout seul via l’API MQL5 :

- digits, point, tick size, tick value
- volume min / max / step
- stops level, freeze level
- filling mode, trade mode
- spread, sessions

Sur Deriv, le symbole gold peut s’appeler `XAUUSD`, `XAUUSD.std`, etc. Renseigner `InpSymbol` exactement.

Si `volume_min > 0.01`, l’EA **refuse de démarrer**. Il ne viole pas le plafond de 0.01 lot.

## 5. Attacher l’EA

1. Ouvrir le graphique du symbole gold.
2. Timeframe du graphique : indifférent (les TF stratégiques sont des inputs).
3. Autoriser le trading algo : `Outils → Options → Expert Advisors → Autoriser le trading algorithmique`.
4. Glisser `IFVG Sentinel EA` sur le graphique.
5. Cocher `Autoriser le trading live` (même en demo).
6. Vérifier le dashboard : `IFVG SENTINEL` + status `WAITING` / `ANALYZING`.

## 6. Gold-only (défaut Deriv) vs SMT externe

**Défaut : `InpGoldOnlyMode = true`.**

Le robot trade **XAUUSD** (ou le nom Deriv exact renseigné dans `InpSymbol`, ex. suffixe). Il ne dépend **pas** de :

- `USDX`
- `XAGUSD`
- `DXY`
- tout autre instrument

Journal au démarrage :

```
[IFVG] GOLD-ONLY MODE: trading XAUUSD only. External SMT (XAGUSD/USDX) is not a mandatory gate. No fake SMT is computed.
```

Pendant un setup : `SMT = SKIPPED_GOLD_ONLY`. Ce n’est pas une confirmation SMT. USDX/XAGUSD absents **ne bloquent pas** un setup gold.

Aucun ordre n’est envoyé sur un symbole autre que `InpSymbol`.

### Mode multi-symboles (optionnel / futur)

Si `InpGoldOnlyMode = false`, le filtre SMT historique est conservé :

- `InpSMTSymbol1 = XAGUSD` (corrélation positive)
- `InpSMTSymbol2 = USDX` (corrélation inverse)

Sur Deriv, `USDX` n’existe souvent pas. Dans ce mode uniquement :

- SMT **obligatoire** + symbole absent = `NO TRADE — SMT missing`
- fournir un symbole Deriv valide, ou `SMT_OPTIONAL` / `SMT_DISABLED`

### Journal de chaîne (pas à chaque bougie)

À une transition / un arrêt de setup, le journal peut afficher :

```
[IFVG] HTF = PASS
[IFVG] PD ARRAY = PASS
[IFVG] LIQUIDITY = PASS
[IFVG] SWEEP = PASS
[IFVG] SMT = SKIPPED_GOLD_ONLY
[IFVG] CISD = PASS|FAIL
[IFVG] DISPLACEMENT = PASS|FAIL
[IFVG] FVG = PASS|FAIL
[IFVG] INVERSION = PASS|FAIL
[IFVG] IFVG = PASS|FAIL
[IFVG] RETEST = PASS|FAIL
[IFVG] ENTRY GATES = PASS|FAIL
[IFVG] RR = PASS|FAIL
[IFVG] FINAL DECISION = TRADE | NO TRADE
```

Si inversion échoue, la raison exacte est dans `FINAL DECISION` / `INVERSION FAIL`.
Si RR échoue : `actual 1:x.xx target 1:y.y`.

## 7. Persistence du cooldown

Le cooldown 8h utilise les **Global Variables** du terminal :

```
IFVG_SENTINEL_<magic>_<symbol>_CONSEC_SL
IFVG_SENTINEL_<magic>_<symbol>_CD_START
IFVG_SENTINEL_<magic>_<symbol>_CD_END
```

Elles survivent à un redémarrage de MT5. Ne pas les supprimer manuellement pendant un cooldown.

## 8. Checklist avant demo

- [ ] Compilation sans erreur
- [ ] Self-test OnInit = PASS (input `InpRunSafetySelfTest = true`)
- [ ] Journal Experts : `[IFVG] IFVG Sentinel EA v1.0.0 init`
- [ ] `volume_min` ≤ 0.01
- [ ] Dashboard visible
- [ ] AutoTrading (bouton) vert
- [ ] Compte **DEMO** uniquement
