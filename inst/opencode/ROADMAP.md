# Roadmap stockToolsR

Améliorations identifiées durant le développement, à traiter ultérieurement.
Backlog : performance, robustesse, qualité des données, dette technique.

---

## Révision du cron — `inst/script2/` (priorité)

Réécriture complète du pipeline actuel (`inst/script/`), un fichier à la fois, dans `inst/script2/`.
Les scripts actuels restent intacts pendant la révision.

### Fiabilité (décisions prises pour la nouvelle version)

- [x] **Helper DRY** : une fonction `fmp_get()` dans `00_api.R` centralisant GET FMP + header clé + status 200 + retry + `Sys.sleep` + log. Remplace les ~10 appels dupliqués.
- [x] **Clé API par header** (pas dans l'URL) pour éviter la fuite dans les logs.
- [x] **Clé API via `Sys.getenv()`** — jamais en dur.
- [x] **Erreurs non silencieuses** : logger le motif d'échec (statut HTTP) + retry avant abandon, au lieu de retourner `NULL` sans trace.
- [x] **Transactions** pour les DELETE+INSERT non-atomiques — fait : `01_profiles` (force), `02_splits` (DELETE multi-tables), `04_statements` (écriture 6 tables).
- [x] **TRUNCATE avant écriture sans transaction** dans les tables `_build` — corrigé : toutes les écritures `_build` sont maintenant transactionnelles (TRUNCATE + append dans `dbWithTransaction`), via les fonctions `v2` (`tidy_stmts2`, `valuation_stockprice2`, `cagr_stockprice2`, `cagr_stmts2`, `build_dividendes_build2`, `build_quality_build2`).
- [x] **`bind_rows` sur listes `NULL`** (états financiers) — corrigé : `fmp_get` retourne NULL et `get_stmts_cie()` filtre les appels échoués avec `purrr::compact`.

### Logging (consultable via l'app Shiny)

- [x] **Table `cron_log` PostgreSQL** : résumé du run (une ligne par run : statut, nb_ok, nb_warn, nb_err, started_at, finished_at) — vérification en un coup d'œil.
- [x] **Détail sur S3** : fichiers journels `.rds` dans `stockToolsR/logs/` — diagnostic et historique long.
- [ ] **Module Shiny de consultation des logs** (projet en cours) : afficher le résumé du dernier run (table `cron_log`) + accès au détail des erreurs (fichier `.rds` jour sur S3). Fonctions à écrire dans `R/`.

### Points à traiter au fil de la révision

- [ ] Fuite de clé API en dur dans `inst/script/0-plan.R` : retirer la clé hardcodée, passer par `Sys.getenv()`.
- [ ] Valeurs magiques (ex: fenêtre `375` dans `valuation_stockprice`) — rendre paramétrables.
- [ ] **Fenêtre du calendrier de publications (`03_earning_cal.R`)** : `-5/+15` jours est adapté à un cron quotidien, mais crée un « trou » en cas d'arrêt prolongé du script. Évaluer une fenêtre plus large (-2 mois/+1 mois) ou un rattrapage pour couvrir les publications d'une période d'arrêt.

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

- [ ] `3-splits_processing.R` : vérifier que `fail_split()` est bien appelée en cas d'erreur
  - La fonction existe mais la gestion d'erreur du pipeline n'est pas complète

---

## Qualité des données

- [ ] Détection des doublons dans `financial_stmts_build` après un split + re-import
  - Vérifier l'unicité de `(symbol, date)` après reconstruction TTM

- [ ] Validation post-`tidy_stmts()` sur quelques grandes compagnies (AAPL, MSFT)
  - Vérifier que les valeurs TTM reconstruites sont cohérentes (ex: via `assertr`)

---

## Périmètre des compagnies

- [ ] **Élargir au-delà du S&P 500** : le pipeline est pensé pour le S&P 500 (`GetSP500Stocks()` dans `0-plan.R`). Évaluer un support de 2000 à 4000 compagnies USA (abonnement FMP limité aux compagnies USA). Nécessite de rendre la liste de tickers flexible (configurable) et de vérifier les limites d'appels API (300/min).

- [ ] **Ajout manuel/semi-manuel de compagnies canadiennes** : FMP (abonnement actuel) ne couvre pas le Canada. Souhait : pouvoir ajouter manuellement des compagnies canadiennes (pour alertes / watchlist). Nécessite une source de données pour les tickers CA + une méthode d'ajout (via watchlist ou config).

---

## Fonctionnalités futures

- [ ] Externaliser les `keep_cols_*` de `9-tidy_stmts.R` dans un fichier de config sur S3
  - Évite de modifier le script pour changer les colonnes conservées

- [ ] Étape `10-ratios.R` — calcul de ratios financiers
  - P/E, EV/EBITDA, etc. à partir de `financial_stmts_build` + `stockprice`
  - Référence : `inst/R_temp/calcul_ratio.R`

- [ ] Module Shiny — objectif final du projet (package séparé)
  - Consommera `financial_stmts_build`, `stockprice`, `dividendes`

- [ ] Tableau Croissance (`mod_finance4`) — ajouter des lignes CAGR
  - Nécessite d'abord d'ajouter les colonnes au pipeline CAGR (`10-cagr_stmts.R` ou équivalent)
  - Colonnes cibles : `bs_totalassets`, `bs_totalliabilities`, `cf_netcashprovidedbyoperatingactivities`
  - Optionnel : variation des actions en circulation (`is_weightedaverageshsout`)
  - Préfixes attendus dans `cagr_stmts_build` : `cagr_1_bs_totalassets`, `cagr_3_bs_totalassets`, etc.

---

## Dette technique — mod_finance4

- [ ] **Révision complète de `mod_finance4.R`** (~1000 lignes, principalement généré par IA)
  - Lire et comprendre chaque section avant d'aller plus loin
  - Objectif : s'approprier le code, pas juste le faire fonctionner

- [ ] **Séparation en plusieurs fichiers** une fois la révision faite
  - Candidats : `helpers_finance_ui.R` (filter defs, builders, formateurs),
    `helpers_finance_display.R` (tableaux, coloration), `mod_finance4.R` (UI + server seulement)

- [ ] **Schémas CREATE TABLE manquants** — aucune définition SQL explicite pour les tables `_build`
  - Si la DB est recréée, les colonnes/types devront être reconstruits à la main
  - Ajouter un fichier `inst/sql/create_tables.sql` avec les définitions complètes

---

## Idées à évaluer

- [ ] Préréglages de filtres sauvegardables par l'utilisateur (projet futur Shiny)
- [ ] `cagr_10y` prix dans `cagr_price_build` — actuellement placeholder `NA_real_`