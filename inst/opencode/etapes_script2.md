# Étapes du cron — `inst/script2/`

Documentation de chaque fichier du pipeline quotidien. Le cron est exécuté sur
le VPS tous les matins via `crontab`, lancé par :

```
Rscript inst/script2/0-plan.R
```

L'ordre d'exécution est défini par `0-plan.R`. Chaque fichier suivant décrit
son rôle, ce qu'il lit/écrit et ses dépendances.

---

## `0-plan.R` — Orchestrateur du cron

**Rôle** : point d'entrée unique. Prépare l'environnement (connexions, clé API,
tickers), puis exécute séquentiellement les étapes `01_` à `09_` dans un bloc
`tryCatch`. Il centralise la gestion du cycle de vie du run : log, statut final.

### Séquence d'exécution

1. **Bibliothèques** : `here`, `DBI`, `RPostgres`, `dplyr`, `dbplyr`, `s3db`,
   `lubridate`, `devtools`, `stringr`, `BatchGetSymbols`.
2. **`devtools::load_all()`** : charge le package pour réutiliser les fonctions
   de `R/` (notamment `fmp_get()`, `init_log()`, `log_append()`, `log_flush()`).
3. **Connexion S3** : `s3_connection_HL()` puis lecture de
   `config_global.rds` (via `s3db::s3readRDS_HL`) pour la config protegR2.
4. **Clé API FMP** : lue depuis `config_global$stockToolsR$key_fmp_api` —
   jamais en dur.
5. **Tickers S&P 500** : `BatchGetSymbols::GetSP500Stocks()` (les `.` remplacés
   par `-` pour la norme Yahoo/FMP). NOTE : vieux package, solution plus fiable
   à évaluer (voir `ROADMAP.md`).
6. **Connexion PostgreSQL** : `dbConnect()` sur `config_global$protegR2$db`.
   En local, on passe par un tunnel SSH ; sur le VPS, `host` est localhost.
   `on.exit(dbDisconnect(con))` garantit la fermeture.
7. **Log** : `init_log()`, `log_env$started_at <- Sys.time()`.
8. **Exécution des étapes** dans `tryCatch` : `source()` de `01_profiles.R`
   → `02_splits.R` → `03_earning_cal.R` → `04_statements.R` → `05_pricediv.R`
   → `06_tidy_stmts.R` → `07_valcagr.R` → `08_divbuild.R` → `09_quality.R`.
   En cas d'erreur, un `log_append(etape = "global", statut = "ERROR", ...)`
   est enregistré et la chaîne s'arrête (le `tryCatch` renvoie `FALSE`).
9. **`log_flush(con)`** : persiste le détail (S3, `stockToolsR/logs/YYYY-MM-DD.rds`)
   et le résumé (table PostgreSQL `cron_log`).

### Production

- Détail journalier du log : `stockToolsR/logs/YYYY-MM-DD.rds` (S3).
- Résumé : une ligne dans `cron_log` (PostgreSQL, consultable par `SELECT`).
- Un échec d'une étape ne bloque pas le flush du log : `log_flush()` est appelé
  après le `tryCatch`, quoi qu'il arrive.

### Dépendances

- Connexion S3 fonctionnelle (protegR2) et PostgreSQL.
- Clé API FMP dans `config_global.rds`.
- Fonctions de log de `R/0-api_fcts.R` chargées par `load_all()`.
- Liste de tickers S&P 500 disponible via `BatchGetSymbols`.

---

## `01_profiles.R` — Profils des compagnies

**Rôle** : vérifie la présence des profils de chaque ticker dans
`cies_profile_orig`, ajoute les manquants, rafraîchit tournativement les plus
anciens, puis reconstruit `cies_profile_build`.

**Variables attendues** (posées par `0-plan.R`) : `con`, `tickers`,
`key_fmp_api`, `log_env`.

### Sous-étapes

- **Helper `upsert_profile(symbol, con, key_fmp_api, force)`** : appelle FMP
  `profile` via `fmp_get()`, normalise (noms en minuscules, ajoute
  `symbol` si absent, `last_updated <- Sys.Date()`), puis :
  - si la ligne existe **et** `force = TRUE` → remplacement atomique
    (DELETE + INSERT dans `dbWithTransaction`) ;
  - sinon → simple INSERT (`append = TRUE`).
  - Logge chaque résultat (`OK` / `ERROR`).
- **1a — Profils manquants** : `setdiff(tickers, cies_in_db)` → `upsert_profile`
  pour chacun, avec `Sys.sleep(0.2)` (limite FMP).
- **1b — Rafraîchissement tournant** : sélectionne les **3 profils les plus
  anciens** (`arrange(last_updated)` — les `NULL` passent en premier) parmi
  `tickers`, puis `upsert_profile(..., force = TRUE)`. Rotation sur 3/jour →
  ~500 tickers ≈ 170 jours pour un tour complet.
- **1c — Reconstruction de `cies_profile_build`** : `collect()` des colonnes
  retenues depuis `cies_profile_orig`, puis `dbWriteTable(overwrite = TRUE)`.
  Erreur → log + `stop()`.

### Production

- `cies_profile_orig` : ajout / remplacement ciblé par `symbol`.
- `cies_profile_build` : reconstruite entièrement à chaque run (overwrite).

### Points de vigilance (vérification)

- `cies_in_db` (1a) : `pull(symbol)` sur la **table entière**, sans filtre
  `symbol %in% tickers` — le diff est donc fait sur tous les tickers en base.
  Incohérence mineure avec 1b, qui filtre bien sur `tickers`.
- `force = FALSE` avec ligne déjà existante (cas 1a si un ticker apparaît alors
  qu'il est déjà présent) → doublon potentiel : aucune vérification d'unicité
  avant INSERT simple. Le flot nominal (1a sur manquants) évite ce cas, mais
  un `force` implicite n'est pas garanti.
- `upsert_profile` peut retourner `FALSE` sans bloquer la boucle (les échecs
  API sont loggés puis le run continue) — cohérent avec la philosophie
  « pas de plantage global sur erreur ponctuelle ».

### Dépendances

- `R/0-api_fcts.R` (`fmp_get`, `log_append`) — chargé par `load_all()`.
- FMP endpoint `profile`.

---

## `02_splits.R` — Détection et traitement des splits

**Rôle** : gère les fractionnements d'actions (splits). Deux phases :
- **Phase A — Détection** (uniquement le **mardi**) : appelle le calendrier des
  splits FMP sur ±10 jours, ne garde que les tickers S&P 500, calcule le ratio
  et insère les nouveaux splits en statut `pending` dans `split_log`.
- **Phase B — Traitement** (tous les jours) : pour chaque split `pending` dont
  la date est passée, supprime les données du symbol (états financiers, prix,
  dividendes) afin que les étapes suivantes les re-téléchargent.

**Variables attendues** (posées par `0-plan.R`) : `con`, `tickers`,
`key_fmp_api`, `today`, `log_env`.

### Phase A — Détection (`mardi` uniquement)

- Condition : `format(today, "%u") == "2"`.
- `fmp_get("splits-calendar", from = today-10, to = today+10)`.
- Filtre `symbol %in% tickers`, calcule `split_ratio = numerator / denominator`,
  normalise `split_date`.
- INSERT dans `split_log` en `status = 'pending'`, avec
  `ON CONFLICT (symbol, split_date) DO NOTHING` (idempotent : pas de doublon).
- Les splits détectés le mardi couvrent les dates J−10 à J+10 : le traitement
  (Phase B) pourra ensuite s'en charger dès que la date est passée.

### Phase B — Traitement (`pending` expirés)

- `get_pending_splits(con, horizon_days = -1)` : splits `status = pending` et
  `split_date <= Sys.Date() - 1`, triés par date (`R/2-cron_split_fcts.R:124`).
- Pour chaque split, **transaction atomique** :
  1. DELETE du symbol dans les 8 tables : `qts_*_stmts_orig`,
     `fy_*_stmts_orig`, `stockprice`, `dividendes`.
  2. `confirm_split()` → `status = 'confirmed'`, `confirmed_date` et
     `rewrite_date` = aujourd'hui.
  - Tout ou rien : si `confirm_split` échoue, les DELETE sont annulés (rollback).
- En cas d'erreur : `fail_split()` → `status = 'failed'` + notes = message
  d'erreur. Le run continue (les autres splits sont traités).

### Pourquoi supprimer puis re-télécharger

Après un split, l'historique de prix est réajusté par la source (Yahoo/FMP).
En **supprimant** les données du symbol à la date effective du split, les
étapes suivantes (`05_pricediv`, `04_statements`, etc.) les re-téléchargent
réajustées — évitant de mélanger des valeurs pré/post-split non cohérentes.

### Production

- `split_log` : lignes `pending` → `confirmed` / `failed`, avec dates de
  détection, confirmation et réécriture.
- Déclenche indirectement le re-téléchargement des données du symbol dans les
  étapes 4 et 5 (les tables ont été vidées).

### Points de vigilance (vérification)

- **Phase A le mardi seulement** : un split survenant hors fenêtre de détection
  (arrêt prolongé, ≥10 jours sans run le mardi) pourrait être manqué. Voir
  la fenêtre `-5/+15` du calendrier de publications — même réflexion à avoir.
- `get_pending_splits(horizon_days = -1)` : `Sys.Date() - 1`, donc un split
  **daté du jour** n'est pas traité le jour même (il le sera le lendemain) —
  cohérent pour laisser le réajustement se propager.

### Dépendances

- `R/0-api_fcts.R` (`fmp_get`, `log_append`).
- `R/2-cron_split_fcts.R` (`get_pending_splits`, `confirm_split`,
  `fail_split`).
- FMP endpoint `splits-calendar`.
- Tables nettoyées : `qts_*_stmts_orig`, `fy_*_stmts_orig`, `stockprice`,
  `dividendes`.

---

## `03_earning_cal.R` — Calendrier de publications

**Rôle** : met à jour le calendrier de publications (earnings) et le fichier de
suivi `cies_order.rds` sur S3. Exécuté **uniquement le mardi**
(`format(today, "%u") == "2"`).

**Variables attendues** (posées par `0-plan.R`) : `con`, `tickers`,
`key_fmp_api`, `today`, `log_env`.

### Fonctionnement

1. **Fenêtre** : `fmp_get("earnings-calendar", from = today-5, to = today+15)`.
   Couvre les publications de 5 jours avant à 15 jours après le mardi.
2. **Filtre** : garde les `symbol %in% tickers`, trie par `date`.
3. **Suivi `cies_order.rds`** (sur S3, `stockToolsR/data/`) :
   - s'il **n'existe pas** → `init_cies_order()` : crée le fichier avec chaque
     compagnie en `inc_status` / `bs_status` / `cf_status = "pending"` ;
   - s'il **existe** → `update_cies_order()` : **ajoute uniquement les
     nouvelles compagnies** absentes du suivi (les existantes ne sont pas
     modifiées).

### Rôle de `cies_order.rds`

Suivi par compagnie des 3 états financiers (`inc_status`, `bs_status`,
`cf_status` = `pending` / `complete`). Champs : `symbol`, `reportDate`,
`reportDate_mod`, + les 3 statuts. Utilisé par l'étape 4 (`04_statements.R`)
pour savoir **quels états sont attendus** et passer ceux dont la publication
est complète. Le fichier est lu depuis S3 (aucune table DB dédiée).

### Production

- `cies_order.rds` sur S3 : enrichi à chaque mardi des nouvelles publications.
- Aucune écriture PostgreSQL dans cette étape.

### Points de vigilance (vérification)

- **Fenêtre `-5/+15` jours** (même remarque que ROADMAP) : adaptée à un cron
  quotidien, mais en cas d'**arrêt prolongé** (>5 j avant / >15 j après), des
  publications peuvent être manquées et jamais rattrapées. Le fichier ne
  retrace pas l'historique des publications passées non vues.
- **Idempotence partielle** : `update_cies_order` n'ajoute que les nouvelles
  compagnies (`!symbol %in% cies_order$symbol`) — pas de risque de doublon,
  mais aussi **pas de mise à jour** si une compagnie déjà présente change de
  date de publication.
- **Fonction legacy non utilisée** : `fmp_get_earnings_calendar()`
  (`R/3-cron_earning_cal_fcts.R:27`) contient une clé API dans l'URL et un
  endpoint codé en dur — **non appelée** par le script révisé, qui utilise
  `fmp_get()` (header). À supprimer ou ignorer (voir points_releves).

### Dépendances

- `R/0-api_fcts.R` (`fmp_get`, `log_append`).
- `R/3-cron_earning_cal_fcts.R` (`init_cies_order`, `update_cies_order`).
- S3 : `cies_order.rds` sous `stockToolsR/data/`.
- FMP endpoint `earnings-calendar`.

---

## `04_statements.R` — Import et vérification des états financiers

**Rôle** : importe les états financiers (income / balance / cash-flow,
trimestriels et annuels) depuis FMP dans les 6 tables `*_stmts_orig`, puis
vérifie la bonne réception via `check_filing_exists()` et met à jour le suivi
`cies_order.rds`.

**Variables attendues** (posées par `0-plan.R`) : `con`, `tickers`,
`key_fmp_api`, `today`, `log_env`.

### Cas traités

- **Cas 1 — Nouvelles compagnies / post-split** (absentes de la DB) : import
  **complet** de `limit = 12` ans pour chaque ticker manquant dans
  `qts_income_stmts_orig`.
- **Cas 2 — Publications prévues** : pour les compagnies de `cies_order` avec
  `reportDate_mod <= today` **et déjà présentes en DB**, import **récent**
  (`limit = 4` rapports) avec **remplacement** de l'existant.

### Fonctionnement détaillé

1. **Récupération (`get_stmts_cie`)** : pour un symbol, appelle FMP sur
   `income` / `balance-sheet` / `cash-flow`, chacune pour Q1–Q4 (via
   `purrr::map` + `compact()`) puis FY. Les appels échoués sont **exclus** (pas
   de `NULL` cassant `bind_rows`). Retourne une liste `income`, `balance`,
   `cashflow`, `annual`.
2. **Écriture (`write_stmts_tables`)** : en **transaction**, écrit les 6
   tables `*_orig`. Normalise `date` (ymd) et noms de colonnes (minuscules).
   Si `replace = TRUE`, DELETE du symbol avant INSERT (remplacement atomique).
   Les tables vides (`NULL`/`nrow == 0`) sont sautées.
3. **Vérification post-import** : pour chaque compagnie de `cies_order` avec
   `reportDate_mod <= today`, `check_filing_exists(con, sym, reportDate, ±7 j)`
   renvoie `inc_status`/`bs_status`/`cf_status` = `complete` ou `incomplete`
   (présence d'un `filingdate` dans la fenêtre). Mise à jour du suivi :
   - statuts enregistrés dans `cies_order` ;
   - si **incomplet** → `reportDate_mod = Sys.Date() + 3` (nouvel essai dans
     3 jours) ;
   - si **complet** (les 3) → la compagnie est **retirée** de `cies_order`
     (filtre final), puis le fichier est resauvé sur S3.

### Cycle de vie d'un statut (`pending → incomplete → complete`)

Confirmé par la lecture :
- `03` initialise les statuts à **`pending`** ;
- `04` (vérification) les fait passer à **`incomplete`** (état présent en DB
  pas encore trouvé dans la fenêtre) ou **`complete`** (retrouvé) ;
- une compagnie `incomplete` est **reportée de +3 jours** (retry) tant qu'elle
  n'est pas complète ; une fois `complete` sur les 3 états, elle est **retirée**
  du fichier.

### Production

- 6 tables `_orig` : `qts_income_stmts_orig`, `qts_balance_stmts_orig`,
  `qts_cf_stmts_orig`, `fy_income_stmts_orig`, `fy_balance_stmts_orig`,
  `fy_cf_stmts_orig`.
- `cies_order.rds` (S3) : statuts mis à jour, retraits des compagnies
  complètes.

### Points de vigilance (vérification)

- **`reportDate` vs `reportDate_mod`** : la vérification (`check_filing_exists`)
  compare les `filingdate` à **`reportDate`** (date annoncée), pas à
  `reportDate_mod`. Cohérent si `reportDate_mod` est un simple repère de
  retry.
- **Cas 1 sans `cies_order`** : les nouvelles compagnies sont importées mais
  **non suivies** dans `cies_order` (pas de vérification ni de retry) — elles
  ne seront mises à jour qu'au prochain mardi où elles apparaissent dans le
  calendrier.
- **Pas de mise à jour des `_orig` pour les compagnies non publiantes** :
  seuls les nouveaux tickers (Cas 1) et les publications prévues (Cas 2) sont
  rafraîchis. L'historique des autres reste figé (acceptable, données stables).

### Dépendances

- `R/0-api_fcts.R` (`fmp_get`, `log_append`).
- `R/4-cron_statements_fcts.R` (`check_filing_exists`).
- FMP endpoints : `income-statement`, `balance-sheet`, `cash-flow`.
- S3 : `cies_order.rds`.
- `purrr` (map/compact), `lubridate` (ymd).

---

## `05_pricediv.R` — Prix boursiers et dividendes

**Rôle** : met à jour (1) les prix quotidiens via Yahoo Finance (`tidyquant`)
dans `stockprice`, et (2) les dividendes via FMP dans `dividendes`.

**Variables attendues** (posées par `0-plan.R`) : `con`, `tickers`,
`key_fmp_api`, `today`, `log_env`.

### PRIX (Yahoo Finance / `tq_get`)

1. **Tickers non disponibles** : chargés depuis
   `non_available_stockprice.rds` (S3) ; liste par défaut
   `c("MRO","SQ","ATVI","TWX","TWTR","VIAC")` si le fichier n'existe pas
   (créé à la volée). `tickers_scope = setdiff(tickers, non_available)`.
2. **Dernière date de marché** : `tq_get("AAPL", ...)` sur les 7 derniers
   jours, `max(date)`.
3. **Tickers à jour** : ceux dont `max(date)` dans `stockprice` est `>=`
   dernière date de marché.
4. **Tickers à mettre à jour** (`setdiff`) → `update_stockprice(con, ...)`.

`update_stockprice()` (`R/5-cron_pricediv_fcts.R:32`) gère deux sous-cas :
- tickers **déjà présents** : `tq_get` depuis `min(last_date)+1`, élimine la
  date du jour et les doublons (`anti_join`) ;
- tickers **nouveaux / post-split** : `tq_get` sur **12 ans**.

### DIVIDENDES (FMP)

1. **Tickers avec dividendes** : depuis `cies_profile_orig`, ceux avec
   `lastdividend > 0`.
2. **Cas 1 — tickers déjà présents** dans `dividendes` : un seul appel
   `dividends-calendar` depuis `max(date)` de la table jusqu'à hier, filtre
   sur les existants, anti-join contre la table, INSERT des nouveaux.
3. **Cas 2 — tickers absents** : boucle `dividends` par compagnie (`limit =
   500`, ~12 ans) via `fmp_get()` avec `Sys.sleep(0.2)`, puis anti-join et
   INSERT.

### Production

- `stockprice` : delta quotidien (ou full 12 ans pour nouveaux/post-split).
- `dividendes` : ajouts incrémentaux (pas de remplacement).

### Points de vigilance (vérification)

- **Fonctions legacy non utilisées dans `R/5-cron_pricediv_fcts.R`** :
  `fmp_dividends_company_get()`, `fmp_dividends_calendar_get()` — le script
  révisé appelle **directement** `fmp_get()` pour les dividendes. Ces
  fonctions legacy : clé API **dans l'URL** (fuite), non appelées →
  candidates à suppression (voir points_releves). `update_dividendes()` a
  déjà été **supprimée**.
- **Delta prix** : `tq_get` télécharge depuis `min(last_date)` global sur les
  tickers existants (pas par ticker) — potentiellement beaucoup de données
  récupérées pour un petit delta, mais filtré par anti-join avant INSERT.
- **`update_stockprice` élimine la date du jour** (`filter(date != to_date)`)
  : cohérent — on n'insère que des données de marché complètes (la journée en
  cours n'est pas encore clôturée).

### Dépendances

- `R/0-api_fcts.R` (`fmp_get`, `log_append`).
- `R/5-cron_pricediv_fcts.R` (`update_stockprice`).
- `tidyquant` (`tq_get`, Yahoo Finance), `purrr`, `dplyr`.
- FMP endpoints : `dividends-calendar`, `dividends`.
- S3 : `non_available_stockprice.rds`.

---

## `06_tidy_stmts.R` — Reconstruction `financial_stmts_build` (TTM)

**Rôle** : reconstruit entièrement la table dérivée `financial_stmts_build` en
**TTM** (trailing 12 mois) à partir des tables brutes `*_stmts_orig`. C'est la
**première table `_build`** du pipeline : elle transforme les états financiers
trimestriels/annuels bruts en une série normalisée, en un row par
`(symbol, date)`.

**Variables attendues** (posées par `0-plan.R`) : `con`, `log_env`.

### Colonnes conservées (projection)

Définies dans le script (`06_tidy_stmts.R:18-46`) puis passées à
`tidy_stmts2()` :

- **`keep_cols_gen`** (8, communes) : `date`, `symbol`, `reportedcurrency`,
  `cik`, `filingdate`, `accepteddate`, `fiscalyear`, `period`.
- **`keep_cols_is`** (13, income) : `revenue`, `grossprofit`,
  `interestincome`, `interestexpense`, `depreciationandamortization`,
  `ebitda`, `ebit`, `operatingincome`, `netincome`, `eps`, `epsdiluted`,
  `weightedaverageshsout`, `weightedaverageshsoutdil`.
- **`keep_cols_bs`** (10, balance) : `totalcurrentassets`,
  `totalnoncurrentassets`, `totalassets`, `totalcurrentliabilities`,
  `totalnoncurrentliabilities`, `totalliabilities`,
  `totalstockholdersequity`, `shorttermdebt`, `longtermdebt`, `totaldebt`.
- **`keep_cols_cf`** (5, cash flow) : `stockbasedcompensation`,
  `netcashprovidedbyoperatingactivities`,
  `netcashprovidedbyinvestingactivities`,
  `netcashprovidedbyfinancingactivities`, `freecashflow`.

### Logique TTM (`tidy_stmts2`, `R/7-cron_tidy_stmts2_fcts.R`)

- **Income** (`:66-98`) : somme glissante sur 4 trimestres
  (`slider::slide_sum(before = 3, complete = TRUE)`) par symbol, en excluant
  les actions en circulation. Les entrées trimestrielles Q4 sont **remplacées
  par les FY** annuels (anti_join + bind_rows). Préfixe `is_`.
- **Balance** (`:102-121`) : **snapshot** (pas de rolling sum — un bilan n'est
  pas cumulatif). Anti-join sur `(date, symbol)` pour ne garder que les
  trimestres non couverts par un FY, puis bind_rows FY. Préfixe `bs_`.
- **Cash flow** (`:125-157`) : même logique rolling sum 4T que l'income,
  remplacement des Q4 par FY. Préfixe `cf_`.
- **Jointure finale** (`:161-183`) : left-join income/balance/cashflow sur
  `(date, symbol)`, puis normalisation `period = "Q4" → "FY"`. Pour chaque
  symbol, on ne conserve que la `period` de la **ligne la plus récente**
  (`slice_max(date)`) — élimine les lignes intermédiaires.
- **Colonnes calculées** (`:166, 185-190`) :
  - `caf = is_netincome + is_depreciationandamortization +
    cf_stockbasedcompensation` (cash available for the firm) ;
  - marges : `m_brut = is_grossprofit/is_revenue`, `m_ebitda =
    is_ebitda/is_revenue`, `m_net = is_netincome/is_revenue`.

### Écriture (transactionnelle)

- Si la table existe : `TRUNCATE` + append dans `dbWithTransaction` — si
  l'écriture échoue, le TRUNCATE est annulé et l'ancienne table est
  **préservée**.
- Si elle n'existe pas (première fois) : création par overwrite.

### Production

- `financial_stmts_build` : reconstruite de zéro à chaque run (TRUNCATE +
  append).

### Points de vigilance (vérification)

- **`keep_cols_gen` défini dans le script** : le `R/` utilise `NA` par défaut
  (toutes les colonnes) mais le script passe la projection — cohérent avec le
  principe `_build` léger.
- **Performance** : les 6 tables `_orig` sont entièrement `collect()`ées puis
  traitées en mémoire à chaque run. C'est le **point le plus lourd** du
  pipeline (voir ROADMAP : recalcul ciblé par `symbols_updated` à étudier).
- **`fiscalyear` converti en `as.numeric`** (income) mais conservé en caractère
  ailleurs — léger risque de divergence de type selon les états.
- **Normalisation `Q4 → FY`** : le remplacement des Q4 par les FY (anti_join)
  suppose que chaque Q4 trimestriel a bien son équivalent FY annuel — sinon un
  Q4 non couvert reste avec sa propre valeur roulante.

### Dépendances

- `R/0-api_fcts.R` (`log_append`).
- `R/7-cron_tidy_stmts2_fcts.R` (`tidy_stmts2`).
- `slider` (slide_sum), `dplyr`, `lubridate`.
- Tables sources : `qts_*_stmts_orig`, `fy_*_stmts_orig`.

---

## `07_valcagr.R` — Valorisation et CAGR

**Rôle** : reconstruit 3 tables dérivées `_build` de valorisation et de
croissance, à partir de `financial_stmts_build` et `stockprice`.

**Variables attendues** (posées par `0-plan.R`) : `con`, `tickers`, `log_env`.

### Sous-étapes

1. **`valuation_stockprice2(con, tickers, window_months = 18)`** → `valuation_build`
   (bandes de valorisation P/S, P/EBITDA, P/E, P/E dilué).
2. **`cagr_stockprice2(con, tickers, years = c(1, 3, 5, 10))`** → `cagr_price_build`
   (CAGR du prix).
3. **`cagr_stmts2(con, tickers)`** → `cagr_stmts_build` (CAGR des états financiers).

Chaque étape est isolée dans un `tryCatch` : un échec est loggé (`ERROR`),
les autres continuent. Le `OK` final n'est loggé que si les 3 réussissent.

### `valuation_stockprice2` (`R/8-cron_ratios2_fcts.R:34`)

1. Charge `financial_stmts_build`, calcule les per-share :
   `sales_p_share = is_revenue/is_weightedaverageshsout`,
   `ebitda_p_share = is_ebitda/is_weightedaverageshsout`, + `eps`, `eps_dil`
   (dont la date = `filingdate`).
2. Charge `stockprice` (`symbol, date, close`).
3. **`full_join`** prix × états sur `(symbol, date)`, puis
   **`tidyr::fill(ratio_cols, .direction = "up")`** : chaque jour de prix
   hérite du dernier ratio financier disponible (les états sont moins
   fréquents que les prix).
4. **Cutoff** : exclut les dates antérieures à la première donnée financière
   − `window_months` (évite les prix antérieurs à tout ratio).
5. Calcule les ratios : `p_to_s = close/sales_p_share`,
   `p_to_ebitda`, `pe`, `pe_dil`.
6. **Rolling min/max** sur `n_days = round(window_months * 21)` (~378 j ouvrés
   pour 18 mois), via `slider::slide_dbl` par ticker (boucle `purrr::imap` —
   étape la plus longue). `safe_min`/`safe_max` retournent NA si la fenêtre
   entière est NA.
7. **Bandes en prix** : `buy = min_ratio × per-share`, `sell = max_ratio ×
   per-share`, `caution = (buy+sell)/2`. Pour chaque ratio.
8. `drop_na()` + `distinct(symbol, date)`, écriture transactionnelle
   (TRUNCATE + append).

### `cagr_stockprice2` (`:195`)

- Charge `stockprice`, trie par date. Pour chaque symbol, prend la dernière
  ligne (`slice_tail`), et pour chaque horizon `y` : `ref_close` = close le
  plus proche de `date - years(y)`, puis
  `cagr_y = (close/ref_close)^(1/y) - 1`.
- Écrit une ligne par symbol dans `cagr_price_build` (transaction).

### `cagr_stmts2` (`:255`)

- Charge `financial_stmts_build`, crée `period2 = FY → Q4` (grouper les FY
  avec les Q4 pour comparer des points de même fréquence).
- Pour chaque colonne `cols` (`is_revenue`, `is_ebitda`, `is_netincome`,
  `is_epsdiluted`, `is_weightedaverageshsout`, `is_weightedaverageshsoutdil`,
  `bs_totalassets`, `bs_totalliabilities`, `cf_freecashflow`, `caf`), calcule
  `cagr_1_/3_/5_/10_<col>` en utilisant `dplyr::lag(col, 1/3/5/10)` — valeurs
  mises à NA hors de la ligne la plus récente (`date == max(date)`).
- Groupé par `(symbol, period2)`, trié par date — donc `lag` compare bien FY
  vs FY / Q1 vs Q1.
- Ne garde que la **dernière ligne par symbol** (`slice_head(n=1)`), écrit dans
  `cagr_stmts_build` (transaction).

### Production

- `valuation_build`, `cagr_price_build`, `cagr_stmts_build` : reconstruites à
  chaque run (TRUNCATE + append).

### Points de vigilance (vérification)

- **Dépendance au problème 5 de `tidy_stmts2`** : `valuation_stockprice2` et
  `cagr_stmts2` consomment `financial_stmts_build`, dont la granularité est
  conditionnée par le filtre `period == period_ref` (période unique par
  symbol). Voir le point [HAUTE IMPORTANCE] dans `points_releves.md`.
- **`cagr_stmts2` `lag`** : nécessite des données **complètes et contiguës**
  (ex: `lag(col, 3)` suppose que 3 lignes de même `period2` existent bien
  avant). Si des points manquent (compagnie récente, FY manquant), le CAGR est
  calculé sur un intervalle erroné.
- **`cagr_stockprice2`** : `ref_close` = close le plus proche de la date
  cible, pas exactement la date — approximation acceptable.
- **Performance** : `valuation_stockprice2` boucle ticker par ticker avec 8
  appels `slide_dbl` quotidiens chacun — c'est le **bloc le plus lourd** du
  pipeline (voir ROADMAP).

### Dépendances

- `R/0-api_fcts.R` (`log_append`).
- `R/8-cron_ratios2_fcts.R` (`valuation_stockprice2`, `cagr_stockprice2`,
  `cagr_stmts2`).
- `slider`, `tidyr`, `purrr`, `rlang`, `lubridate`, `dplyr`.
- Tables sources : `financial_stmts_build`, `stockprice`.

---

## `08_divbuild.R` — Reconstruction `dividendes_build`

**Rôle** : reconstruit la table dérivée `dividendes_build` — les métriques de
dividendes par compagnie (TTM, forward, CAGR, yield, ratios FCF, drapeaux
Special/Irregular).

**Variables attendues** (posées par `0-plan.R`) : `con`, `log_env`.

### Source (`build_dividendes_build2`, `R/9-cron_dividendbuild2_fcts.R`)

- **`dividendes`** (brut) : historique des versements.
- **`valuation_build`** : dernier `close` par symbol (`DISTINCT ON (symbol)
  ... ORDER BY date DESC`).
- **`financial_stmts_build`** : dernier `cf_freecashflow` et
  `is_weightedaverageshsout` par symbol.

### Logique par symbol (`.calc_div_symbol`, `:23`)

1. **Exclusion** des dividendes `Special` / `Irregular` → `df_reg` (uniquement
   les réguliers : Quarterly, Semi-Annual, Annual, Monthly, Weekly).
2. **`div_ttm`** : somme des `adjdividend` réguliers sur les 12 derniers mois
   (`date >= max_date - 1 an`).
3. **Annualisation positionnelle** : selon la fréquence dominante
   (`freq_dominante = df_reg$frequency[1]`), `n` = nb de paiements/an
   (Quarterly 4, Semi-Annual 2, Annual 1, Monthly 12, Weekly 52, défaut 4).
   `annual_at(offset)` somme les `n` versements décalés de `offset` années.
4. **CAGR** : `cagr_1a/3a/5a/10a = da0/daX^(1/X) - 1` (guard : dénominateur > 0,
   pas de NA).
5. **`croissance_reguliere`** : critère = `cagr_1a >= 0`, `cagr_3a >= 0` et
   `abs(cagr_1a - cagr_3a) < 0.10`.
6. **`div_forward`** : si croissance régulière et `cagr_1a` dispo →
   `div_ttm × (1 + cagr_1a)`, sinon `div_ttm`.
7. **Drapeaux** : `has_special` / `has_irregular` (sur `df_all`, donc incluant
   les non-réguliers), + `last_special_date` / `last_irregular_date`.
8. Si **aucun dividende régulier** : retourne une ligne avec `div_ttm`/`div_forward`/CAGR à `NA`.

### Assemblage et ratios (`build_dividendes_build2`, `:184`)

- `left_join` avec `close_df` et `fcf_df`, `rename(close_ref = close)`.
- **`yield`** = `div_forward / close_ref` (si `close_ref > 0`).
- **`.div_total`** (interne) = `div_ttm × is_weightedaverageshsout` (dividende
  total en $).
- **`fcf_payout`** = `.div_total / cf_freecashflow` (part des FCF distribuée).
- **`fcf_coverage`** = `cf_freecashflow / .div_total` (inverse : couverture).
- `last_updated = Sys.Date()`.
- Écriture transactionnelle (TRUNCATE + append).

### Production

- `dividendes_build` : reconstruite à chaque run (un row par symbol).

### Points de vigilance (vérification)

- **`freq_dominante` = première ligne de `df_reg` trié par date desc** : si la
  fréquence a changé dans le temps (ex: Annual → Quarterly), `n` se base sur
  le versement **le plus récent** — l'annualisation `annual_at()` suppose alors
  un rythme constant qui peut ne pas refléter l'historique.
- **`annual_at(offset)` positionnelle** : elle compte `n` lignes, pas `n`
  trimestres calendaires. Un trou dans l'historique décale la somme.
- **`div_ttm` (fenêtre 12 mois) vs `annual_at` (positionnel)** : deux méthodes
  différentes coexistent. `div_ttm` est basé sur les dates, `cagr` sur les
  positions — cohérent si les versements sont réguliers.
- **Dépendance à 06/07** : `close_ref` vient de `valuation_build` (donc des
  prix) et `cf_freecashflow`/`is_weightedaverageshsout` de
  `financial_stmts_build` (donc du filtre `period_ref`). Un yield FCF dépend de
  la granularité de 06.

### Dépendances

- `R/0-api_fcts.R` (`log_append`).
- `R/9-cron_dividendbuild2_fcts.R` (`build_dividendes_build2`,
  `.calc_div_symbol`).
- `lubridate`, `purrr`, `tibble`, `dplyr`.
- Tables sources : `dividendes`, `valuation_build`, `financial_stmts_build`.

---

## `09_quality.R` — Reconstruction `quality_build`

**Rôle** : reconstruit la table dérivée `quality_build` — un instantané par
company regroupant ratios de qualité, de valorisation et métadonnées de
secteur.

**Variables attendues** (posées par `0-plan.R`) : `con`, `log_env`.

### Sources (5) — `build_quality_build2`, `R/10-cron_quality_build2.R`

1. **`financial_stmts_build`** — dernière période par symbol (`DISTINCT ON`).
2. **`financial_stmts_build`** — moyennes ROA/ROE sur les **5 dernières
   périodes**.
3. **`valuation_build`** — dernier close + bandes buy/sell.
4. **`cagr_stmts_build`** — `cagr_3_is_epsdiluted` (pour le PEG).
5. **`cies_profile_build`** — `sector`, `industry`.

### Ratios de qualité (`stmts_latest`, `:46-64`)

Depuis la dernière période financière :
- `roa = is_netincome / bs_totalassets`
- `roe = is_netincome / bs_totalstockholdersequity`
- `ratio_courant = bs_totalcurrentassets / bs_totalcurrentliabilities`
- `fcf_rev = cf_freecashflow / is_revenue`
- `couv_interet = is_ebit / is_interestexpense` (si `interestexpense > 0`)
- `d_actif = bs_totalliabilities / bs_totalassets` (levier)
- `pppi = bs_totaldebt / bs_totalassets`

### Moyennes 5 ans (`stmts_moy5`, `:69-81`)

- `roa_moy5`, `roe_moy5` : moyenne (na.rm) des 5 dernières périodes par symbol.

### Position dans la bande (`valuation_latest`, `:86-107`)

Pour chaque ratio (P/S, P/EBITDA, P/E, P/E dil) :
- `r_* = (close - buy) / (sell - buy)` → position 0..1 dans la bande
  (0 = au buy, 1 = au sell), NA si bande nulle.
- `ratio_moyen = rowMeans(cbind(r_pts, r_ebd, r_pe, r_ped), na.rm = TRUE)`.

### Ratios de valorisation (`result`, `:121-159`)

- `mktcap_m = (is_weightedaverageshsout × close) / 1e6` (marché cap en M$).
- `rev_p_share`, `ebitda_p_share` (per-share).
- `p_to_s_calc`, `p_to_ebd_calc`, `pe_calc` (recalculés ici).
- `peg_calc = pe_calc / (cagr_3_is_epsdiluted × 100)`.
- `last_updated = Sys.Date()`.
- Écriture transactionnelle (TRUNCATE + append).

### Production

- `quality_build` : reconstruite à chaque run (un row par symbol) — **table
  finale** de synthèse du pipeline.

### Points de vigilance (vérification)

- **`roe` / `roa_moy5`** : `bs_totalstockholdersequity` peut être **négatif**
  (vu dans les tables balance, ex: MTD) → ROE faussé/explosé. Pas de guard sur
  dénominateur > 0 ici (contrairement à `couv_interet`).
- **`couv_interet`** : guard sur `interestexpense > 0`, mais pas sur `ebit` —
  un EBIT négatif donne une couverture négative (interprétable).
- **`peg_calc`** : divisé par `cagr_3 × 100` ; dépend du CAGR EPS 3 ans de
  07 (donc du filtre `period_ref`). CAGR nul/négatif → NA (guard `> 0`).
- **`r_*` (position bande)** : suppose `sell > buy` (guard `> 0` sur l'écart) ;
  une bande inversée → NA.
- **`stmts_moy5` (5 dernières périodes)** : dépend de la granularité de 06 —
  avec le filtre FY-only, ce sont 5 **années** ; si on remet les trimestres,
  ce seraient 5 **trimestres** (moyenne sur une fenêtre différente). Même
  sensibilité que le point 2 de 08.

### Dépendances

- `R/0-api_fcts.R` (`log_append`).
- `R/10-cron_quality_build2.R` (`build_quality_build2`).
- Tables sources : `financial_stmts_build`, `valuation_build`,
  `cagr_stmts_build`, `cies_profile_build`.