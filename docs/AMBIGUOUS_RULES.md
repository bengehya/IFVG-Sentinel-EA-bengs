# AMBIGUOUS_RULE — interprétations explicites

La consigne Cursor §43 interdit de transformer silencieusement une notion subjective en règle arbitraire.

Les items ci-dessous étaient **ambiguës** dans le brief. Pour livrer un robot compilable, une interprétation **mesurable** a été choisie et est documentée ici. Ce ne sont pas des « vérités ICT » : ce sont des contrats algorithmiques, révisables.

---

## AMBIGUOUS_RULE 1 — HTF « contexte / biais »

**Ambiguïté :** « le contexte HTF » n’a pas de formule unique (orderflow, daily bias, premium/discount, etc.).

**Choix A (retenu) :** structure HH+HL = bullish, LH+LL = bearish, sinon NEUTRAL → no trade.

**Choix B (non retenu) :** prix au-dessus / en-dessous EMA ou VWAP HTF.

**Choix C (non retenu) :** premium/discount d’un range H4 (50 %).

Pourquoi A : reproductible, sans indicateur externe, invalidable.

---

## AMBIGUOUS_RULE 2 — « PD Array valide »

**Ambiguïté :** quels arrays, quelle fraîcheur, faut-il que le prix y soit encore ?

**Choix retenu :** au moins une zone ACTIVE (FVG 3 bougies **ou** OB d’impulsion ATR) dans la direction du biais, non expirée, non invalidée par close. Le prix n’a **pas** à être à l’intérieur de la zone au moment de l’entrée LTF (le PD array est un filtre de contexte, pas le trigger).

---

## AMBIGUOUS_RULE 3 — « liquidity sweep »

**Ambiguïté :** wick d’1 point au-delà d’un high vs raid institutionnel.

**Choix retenu :** wick au-delà d’un seuil en points **et** close en deçà du niveau **et** rejet (55 % de la range du côté opposé) **et** range ≥ ATR × multiplier. Un close through sans rejet = break, pas sweep.

---

## AMBIGUOUS_RULE 4 — SMT gold vs DXY / XAG

**Ambiguïté :** quelle paire, quel décalage de swing, DXY souvent absent chez Deriv.

**Choix retenu :** deux swings confirmés, fenêtre `smt_lookback`. XAG = corrélation positive. `USDX` / DXY = inverse. Symbole manquant + SMT required = no trade (pas de faux SMT).

Le nom Deriv exact de DXY **doit** être fourni par l’utilisateur si différent de `USDX`.

---

## AMBIGUOUS_RULE 5 — CISD

**Ambiguïté :** ICT CISD a plusieurs lectures (close through open of delivery, displacement candle, MSS).

**Choix retenu :** close directionnel qui traverse **à la fois** l’open de la dernière bougie de livraison opposée **et** l’extrême de la bougie de sweep, avec corps ≥ 50 % de la range et ≥ ATR × facteur.

Ce n’est volontairement **pas** « la première bougie verte ».

---

## AMBIGUOUS_RULE 6 — Displacement

**Ambiguïté :** « strong move » n’est pas mesurable.

**Choix retenu :** somme des corps directionnels ≥ ATR × `displacement_atr_mult` sur un nombre borné de bougies après CISD.

---

## AMBIGUOUS_RULE 7 — Quelle FVG inverser ?

**Ambiguïté :** FVG du displacement, FVG adverse du move vers la liquidité, FVG HTF ?

**Choix retenu :** FVG du TF de confirmation **de direction opposée** au setup, ensuite **close through** la zone → IFVG dans la direction du setup. L’entrée n’utilise que cette IFVG, jamais la FVG brute.

---

## AMBIGUOUS_RULE 8 — Retest

**Ambiguïté :** touch du mid, wick only, close inside, ordre limit au bord ?

**Choix retenu :** overlap de la bougie **fermée** du TF d’entrée avec la zone ± tolérance, sans close de l’autre côté (invalidation). Exécution **market** après validation, pas de limit anticipé.

---

## AMBIGUOUS_RULE 9 — Sessions Asian / London / NY

**Ambiguïté :** DST, broker GMT+2 vs UTC.

**Choix retenu :** pas de DST auto. Offset serveur documenté par input. Fenêtres nommées en UTC fixe (voir CONFIGURATION.md).

---

## AMBIGUOUS_RULE 10 — Compte « petit capital »

**Ambiguïté :** 50 USD vs 500 USD changent le risque % mais le brief impose 0.01 lot max.

**Choix retenu :** le lot n’est **jamais** calculé en % du capital. Le volume visé est le min broker, plafonné à 0.01. Un compte trop petit pour 0.01 (margin) → refus d’ordre (`insufficient margin`), pas de réduction « créative » ni de volume supérieur.

---

Si une de ces interprétations doit changer, modifier **ce fichier + le module concerné**, pas un if isolé dans l’Entry Engine.
