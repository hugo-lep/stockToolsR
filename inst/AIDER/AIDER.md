# stockToolsR

Package R pour collecter, stocker et analyser des données financières boursières (S&P 500).

## Mode de travail

- **Branche git : écrire uniquement sur la branche `claude`.** Ne jamais committer sur `master`.
- **Un fichier à la fois.** Ne jamais créer ou modifier plus d'un fichier par échange.
- Toujours proposer et attendre la validation avant de passer au fichier suivant.
- **Ne jamais modifier un fichier sans que l'utilisateur en fasse la demande explicite.**

## Gestion des améliorations

- Les améliorations identifiées durant le développement sont consignées dans **`inst/AIDER/ROADMAP.md`**
- Ce fichier sert de backlog : performance, robustesse, idées à évaluer
- Ne pas encombrer `CLAUDE.md` avec ces items — le garder court et opérationnel

## Architecture générale

- **Données** : Financial Modeling Prep (FMP) + Yahoo Finance (via `tidyquant`)
- **Base de données** : PostgreSQL sur VPS (migration depuis SQLite en cours)
  - En local : tunnel SSH pour accéder au VPS
  - Tables `_orig` = données brutes API ; tables `_build` = données transformées/utilisables
- **Stockage objet** : S3 OVH via le package personnel `s3db`
  - Connexion : `s3db::s3_connection_HL()` (aucune config supplémentaire)
  - Utiliser S3 uniquement pour les petits fichiers de suivi du cron (pas de filtrage SQL nécessaire)
  - Candidat S3 : `cies_order.rds` (fichier de suivi des publications, écrit le mardi, lu quotidiennement)
  - `financial_stmts_build` et `stockprice` restent dans PostgreSQL : le Shiny tourne sur le même VPS, et SQL est nécessaire pour filtrer/assembler avant retour des données
- **Package** : fonctions dans `R/`, scripts d'orchestration dans `inst/script/`
- **Cible finale** : module Shiny dans un projet séparé qui utilisera ce package

## Structure des dossiers

```
R/                    # Fonctions exportées du package (à construire à partir de inst/R_temp/)
inst/
  R_temp/             # Fonctions de référence actuelles — s'en inspirer pour coder
  script_temp/        # Scripts de référence actuels — s'en inspirer pour coder
  script/             # Scripts du cron (destination cible, à construire)
    0-plan.R          # Point d'entrée : source() vers les autres scripts
    1-*.R ... n-*.R   # Étapes séquentielles du pipeline
```

> Les fonctions et scripts ailleurs dans le projet (`inst/dev/`, `inst/data_db/`, `R/` actuel) sont du vieux code conservé temporairement — ignorer pour le nouveau code.

## Contrainte API FMP importante

**Limite : 300 appels/min.** Toujours ajouter `Sys.sleep()` dans les boucles d'appels FMP.
Règle : `Sys.sleep(0.2)` minimum entre chaque appel (= max ~5 tickers/sec).

## Pipeline du cron quotidien (`inst/script/`)

Le cron tourne sur le VPS. Chaque étape est un script sourcé depuis `0-plan.R`.

### Variables globales disponibles dès `0-plan.R`
```r
library(DBI); library(RPostgres); devtools::load_all()
today       <- Sys.Date()
key_fmp_api <- Sys.getenv("key_fmp_api")
tickers     <- tq_index("SP500")$symbol |> setdiff("-") |> head(10)
con         <- dbConnect(...)  # connexion PostgreSQL
```

### Étape 1 — Profils des compagnies
- Vérifier que tous les `tickers` sont dans `cies_profile_orig`
- Manquants → `fmp_profile_add_to_db()` puis `cies_profile_build()`
- Fonctions : `fmp_profile_get()`, `fmp_profile_add_to_db()`, `cies_profile_build()`

### Étape 2 — Détection des splits *(mardis seulement)*
- Appel FMP sur ±10 jours autour d'aujourd'hui → `fmp_splits_calendar_get()`
- Filtrer sur `tickers`, calculer `split_ratio = numerator / denominator`
- Insérer dans `split_log` avec statut `"pending"` → `detect_and_insert_splits()`
- Fonctions : `fmp_splits_calendar_get()`, `insert_split_pending()`, `detect_and_insert_splits()`

### Étape 3 — Traitement des splits pending
- `get_pending_splits(con)` → splits dont `split_date <= today`
- Pour chaque split : effacer dans `qts_income_stmts_orig`, `qts_balance_stmts_orig`,
  `qts_cf_stmts_orig`, `FY_*`, `stockprice`, `dividends`
- Mettre à jour statut → `confirm_split()` ou `fail_split()`
- Fonctions : `get_pending_splits()`, `confirm_split()`, `fail_split()`

### Étape 4 — Calendrier de publications *(mardis seulement)*
- `fmp_get_earnings(from, to, key_fmp_api)` sur une fenêtre -2 mois / +1 mois
- Filtrer sur `tickers`, mettre à jour `cies_order.rds` → `update_cies_order()`
- La table `cies_order` suit : `symbol`, `reportDate`, `reportDate_mod`,
  `inc_status`, `bs_status`, `cf_status` (valeurs : `"pending"` / `"complete"`)
- Fonctions : `fmp_get_earnings()`, `init_cies_order()`, `update_cies_order()`

### Étape 5 — Import des états financiers
- **Nouvelles compagnies ou post-split** (absents des 3 tables `qts_*`) :
  `fmp_get_stmts_new_cie()` → 12 ans d'historique (Q1-Q4 + FY)
- **Publication prévue** (`cies_order` avec `reportDate_mod <= today`) :
  `fmp_get_statement()` → 4 derniers rapports seulement, remplace les existants
- Écriture : `fmp_original_stmts_update()` → `update_sqlite_table()` (upsert par `date` + `symbol`)
- Pause `Sys.sleep(1.2)` après chaque ticker
- Fonctions : `fmp_get_statement()`, `fmp_get_stmts_new_cie()`, `fmp_original_stmts_update()`, `update_sqlite_table()`

### Étape 6 — Vérification post-import des états financiers
- `check_filing_exists(con, symbol, expected_date, tolerance_days = 7)`
- Si `inc_status == "incomplete"` → repousser `reportDate_mod` de +3 jours
- Si tous "complete" → retirer de `cies_order`
- Fonctions : `check_filing_exists()`, `update_cies_status()`

### Étape 7 — Mise à jour des prix (`stockprice`)
- Référence : `tq_get("AAPL", from = today-7)` → trouver `latest_market_date`
- Tickers déjà à jour (dans `stockprice` jusqu'à `latest_market_date`) → skip
- Tickers à mettre à jour → `update_stockprice(con, symbols_to_update)`
  - Déjà présents : `tq_get()` depuis la date la plus ancienne des dernières MAJ
  - Nouveaux/post-split : `tq_get()` depuis 2010-01-01
  - Dédoublonnage par `anti_join(by = c("symbol", "date"))` avant insert
- Exclure : tickers non disponibles sur Yahoo (`non_available_stockprice`)
- Fonctions : `update_stockprice()`

### Étape 8 — Mise à jour des dividendes
- Même logique que les prix, avec `tq_get(tickers, get = "dividends")`

### Étape 9 — Reconstruction `financial_stmts_build`
- `tidy_stmts(con, keep_cols_*)` : joint IS + BS + CF, annualise les trimestriels
  (somme glissante 4 trimestres via `slider`), préfixes `is_`, `bs_`, `cf_`
- Optimisation future : ne reconstruire que les tickers ayant eu de nouvelles lignes

## Fonctions utilitaires clés

| Fonction | Description |
|---|---|
| `update_sqlite_table(con, df, table_name, cols_ref, replace)` | Upsert générique par colonnes de référence |
| `tidy_stmts(con, keep_cols_*)` | Reconstruit `financial_stmts_build` en TTM |
| `update_stockprice(con, symbols)` | MAJ incrémentale ou complète des prix |

## Conventions de code

- Langue : commentaires et messages en français
- Style : `tidyverse` + pipes `|>` (natif) ou `%>%` (magrittr)
- **Préférer le code R au SQL** : effectuer les calculs et manipulations en R plutôt qu'en SQL quand c'est possible (ex: calculs de dates, filtres). Le SQL doit rester simple (SELECT, INSERT, DELETE de base)
- Paramètre de connexion toujours nommé `con`
- Clé API toujours via `Sys.getenv("key_fmp_api")` dans le code final (pas en dur)
- Scripts numérotés `0-plan.R`, `1-*.R`, `2-*.R` … dans `inst/script/`
- Quand les scripts seront stables → encapsuler en fonctions dans `R/`
