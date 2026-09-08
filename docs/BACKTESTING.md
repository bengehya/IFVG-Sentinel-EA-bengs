# Backtesting

## Règle d’or

**Ne jamais mélanger les statistiques RR=3 et RR=4.**

Chaque valeur de `InpTargetRR` est une **configuration distincte**. Relancer le Strategy Tester à chaque fois.

### Configuration A — RR 1:3

```
InpTargetRR = 3.0
```

### Configuration B — RR 1:4

```
InpTargetRR = 4.0
```

Tous les autres paramètres doivent rester identiques pour comparer uniquement l’effet du RR.

## Réglages Strategy Tester

| Champ | Valeur |
|---|---|
| Expert | IFVG Sentinel EA |
| Symbole | XAUUSD (ou symbole Deriv gold) |
| Période | M15 (le robot charge H4 et M1 lui-même ; M15 est un bon TF visuel) |
| Mode | **Chaque tick** (le retest M1 exige plus que « OHLC 1 minute ») |
| Dates | Au moins 3 fenêtres distinctes (voir ci-dessous) |
| Dépôt | Petit capital (ex. 100–500 USD) — le lot restera 0.01 |
| Optimisation | **Non** pour le premier passage |

Le robot n’augmente pas le lot avec le solde. Un dépôt plus grand ne produit pas des lots plus gros.

## Fenêtres historiques à tester séparément

1. Tendance haussière gold
2. Tendance baissière gold
3. Range / compression
4. Semaine de forte volatilité (NFP, FOMC, CPI)

Documenter pour **chaque** fenêtre et **chaque** RR :

- nombre de trades
- win rate / loss rate
- profit factor
- expectancy
- maximum drawdown
- consecutive losses
- average R / total R
- setups valides / setups rejetés

Ces métriques sont imprimées dans le journal à `OnDeinit` / `OnTester` :

```
[IFVG] ======== BACKTEST REPORT (Target RR 1:3.0) ========
[IFVG] Trades: ...
[IFVG] Setups valid: ...  Setups rejected: ...
```

Le custom criterion `OnTester` combine win rate × profit factor × total R. Il n’est **pas** un objectif d’optimisation agressive.

## Ce que le backtest doit prouver

- [ ] Aucun trade > 0.01 lot (colonne volume)
- [ ] Jamais plus de 2 positions simultanées
- [ ] Après 2 SL, trou d’au moins 8 heures sans nouvel ordre
- [ ] Beaucoup de `NO TRADE — ...` dans le journal (signe de discipline, pas un bug)
- [ ] Aucun ordre sans IFVG + retest dans les logs

## Limites du tester

- SMT : le symbole corrélé doit être disponible dans l’historique du tester. Sinon SMT required = 0 trade. C’est conforme.
- Deriv ticks ≠ every-tick modeling quality. Un forward demo reste obligatoire.
- Les Global Variables du tester ne sont pas celles du terminal live. Tester le redémarrage **en demo**, pas seulement en tester.

## Après le backtest

1. Relire `docs/DECISION_JOURNAL.md` et extraire 10 lignes `NO TRADE` + 10 lignes `Position opened`.
2. Vérifier que chaque ouverture a la chaîne complète dans les logs.
3. Seulement ensuite : compte **DEMO** Deriv.
