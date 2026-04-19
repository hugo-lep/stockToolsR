# Roadmap stockToolsR

Améliorations identifiées durant le développement, à traiter ultérieurement.

---

## Performance

- [ ] `tidy_stmts()` : reconstruire uniquement les tickers mis à jour ce jour-là
  - Passer un vecteur `symbols_updated` collecté depuis les étapes 3, 5 et 7
  - `filter(symbol %in% symbols)` avant `collect()` dans chaque table
  - Remplacer `overwrite = TRUE` par un upsert sur `financial_stmts_build`

- [ ] `valuation_stockprice()` : recalculer uniquement les tickers mis à jour ce jour-là
  - Même logique que `tidy_stmts()` : passer `symbols_updated`
  - Les 8 appels `slide_index_dbl()` sur données quotidiennes sont le bloc le plus lourd

- [ ] `1-profiles.R` : `cies_profile_build()` reconstruite entièrement à chaque run
  - Remplacer par un upsert ciblé sur les 3 profils rafraîchis seulement

---

## Robustesse

- [ ] Gestion des erreurs API FMP dans les boucles `purrr::walk/map`
  - Ajouter `tryCatch()` systématiquement pour logger les échecs et continuer sans planter

- [ ] Log des runs du cron — aucune trace persistante des exécutions
  - Ajouter une table `cron_log` (date, étape, statut, message) ou un fichier de log
  - Permettrait de diagnostiquer des problèmes après coup

- [ ] `3-splits_processing.R` : vérifier que `fail_split()` est bien appelée en cas d'erreur
  - La fonction existe mais la gestion d'erreur du pipeline n'est pas complète

---

## Qualité des données

- [ ] Détection des doublons dans `financial_stmts_build` après un split + re-import
  - Vérifier l'unicité de `(symbol, date)` après reconstruction TTM

- [ ] Validation post-`tidy_stmts()` sur quelques grandes compagnies (AAPL, MSFT)
  - Vérifier que les valeurs TTM reconstruites sont cohérentes (ex: via `assertr`)

---

## Fonctionnalités futures

- [ ] Externaliser les `keep_cols_*` de `9-tidy_stmts.R` dans un fichier de config sur S3
  - Évite de modifier le script pour changer les colonnes conservées

- [ ] Étape `10-ratios.R` — calcul de ratios financiers
  - P/E, EV/EBITDA, etc. à partir de `financial_stmts_build` + `stockprice`
  - Référence : `inst/R_temp/calcul_ratio.R`

- [ ] Module Shiny — objectif final du projet (package séparé)
  - Consommera `financial_stmts_build`, `stockprice`, `dividendes`

---

## Idées à évaluer

*(vide pour l'instant)*
