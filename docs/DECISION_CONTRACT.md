# Journal des décisions du robot

Voir aussi `docs/DECISION_JOURNAL.md` pour le format runtime.

Ce fichier liste les **contrats de décision** figés dans le code. Toute modification d’une ligne ici exige un changement de module correspondant.

| ID | Décision | Comportement |
|---|---|---|
| D1 | Qualité > fréquence | Une porte failed = NO TRADE, jamais de raccourci |
| D2 | Lot | min(calculé, input, 0.01) — impossible de trader 0.02+ |
| D3 | Positions | max 2, magic isolé, pas de 3ᵉ « parce que le setup est parfait » |
| D4 | Cooldown | 2 SL → 8h minimum, Global Variables, survit au restart |
| D5 | Revenge | pas de lot↑, pas de RR auto-modifié, pas de SL déplacé pour éviter la perte |
| D6 | Trigger | IFVG retestée seulement, jamais FVG/sweep/SMT/CISD/OB seuls |
| D7 | RR | réel ≥ TargetRR (3 ou 4), sinon refus |
| D8 | Broker Deriv | specs lues à l’init/timer ; volume_min>0.01 = refus d’init |
| D9 | Sessions | timezone documenté, pas de DST silencieux |
| D10 | Un setup = une décision | SetupID hashé ; déjà exécuté = skip |
