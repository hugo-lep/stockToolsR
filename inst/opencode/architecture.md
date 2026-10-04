# Architecture des données — stockToolsR

Document d'architecture décrivant les tables du schéma `stocktools` (PostgreSQL
sur VPS) ainsi que les fichiers de suivi stockés sur S3. Ce document est une
ébauche reconstituée à partir du code (`inst/script2/` et `R/`). Les colonnes
et types indiqués reflètent l'usage dans les requêtes ; les schémas SQL
explicites (`CREATE TABLE`) ne sont pas encore centralisés (voir
`ROADMAP.md` — « Schémas CREATE TABLE manquants »).

---

## Conventions

- **Tables `_orig`** : données brutes issues de l'API (FMP). Écrites au fil de
  l'eau, un delete+insert ciblé par `symbol` lors d'un remplacement.
- **Tables `_build`** : données transformées / utilisables. Reconstruites en
  transaction (TRUNCATE + append) à chaque run du cron.
- Clé primaire logique commune : `(symbol, date)` pour les séries temporelles ;
  `symbol` seul pour les tables "un row par compagnie".
- Connexion : `con` (DBI, RPostgres). Accès via `DBI::Id(schema = "stocktools", ...)`
  ou `dbplyr::in_schema("stocktools", ...)`.

---

## Tables `_orig` (données brutes API)

### `cies_profile_orig`
Profil de chaque compagnie, un row par `symbol`. Source : FMP `profile`.

| Colonne | Type (déduit) | Description |
|---|---|---|
| `symbol` | TEXT | Ticker |
| `companyname` | TEXT | Nom de la compagnie |
| `currency` | TEXT | Devise |
| `cik` | TEXT | CIK |
| `cusip` | TEXT | CUSIP |
| `exchange` | TEXT | Bourse |
| `industry` | TEXT | Industrie |
| `website` | TEXT | Site web |
| `description` | TEXT | Description |
| `sector` | TEXT | Secteur |
| `image` | TEXT | Logo |
| `last_updated` | DATE | Date de mise à jour (ajouté par le cron) |

Colonnes listées dans `01_profiles.R:158` (`build_data`). Le profil FMP brut
contient davantage de colonnes ; seules celles-ci sont reconstruites dans la
table `_build`.

### `qts_income_stmts_orig` / `qts_balance_stmts_orig` / `qts_cf_stmts_orig`
États financiers **trimestriels** (Q1–Q4), un row par `(symbol, date)`. Source :
FMP endpoints `income-statement` / `balance-sheet` / `cash-flow` avec
`period = Q1..Q4` (`04_statements.R:33-43`).

Colonnes générales (`06_tidy_stmts.R:18` — `keep_cols_gen`) :
`date`, `symbol`, `reportedcurrency`, `cik`, `filingdate`, `accepteddate`,
`fiscalyear`, `period`.

Colonnes spécifiques (income) — `06_tidy_stmts.R:24` :
`revenue`, `grossprofit`, `interestincome`, `interestexpense`,
`depreciationandamortization`, `ebitda`, `ebit`, `operatingincome`, `netincome`,
`eps`, `epsdiluted`, `weightedaverageshsout`, `weightedaverageshsoutdil`.

Colonnes spécifiques (balance) — `06_tidy_stmts.R:32` :
`totalcurrentassets`, `totalnoncurrentassets`, `totalassets`,
`totalcurrentliabilities`, `totalnoncurrentliabilities`, `totalliabilities`,
`totalstockholdersequity`, `shorttermdebt`, `longtermdebt`, `totaldebt`.

Colonnes spécifiques (cash flow) — `06_tidy_stmts.R:40` :
`stockbasedcompensation`, `netcashprovidedbyoperatingactivities`,
`netcashprovidedbyinvestingactivities`, `netcashprovidedbyfinancingactivities`,
`freecashflow`.

### `fy_income_stmts_orig` / `fy_balance_stmts_orig` / `fy_cf_stmts_orig`
Mêmes états financiers en version **annuelle** (`period = FY`), un row par
`(symbol, date)`. Source : FMP `...-statement` avec `period = FY`
(`04_statements.R:45-59`). Mêmes colonnes que les tables `qts_*`.

---

## Tables "brutes non `_orig`"

### `stockprice`
Historique des prix boursiers quotidiens, un row par `(symbol, date)`. Source :
Yahoo Finance via `tidyquant::tq_get()` (`05_pricediv.R`, `update_stockprice`).

| Colonne | Description |
|---|---|
| `symbol` | Ticker |
| `date` | Date de trading |
| `open`, `high`, `low`, `close` | OHLC |
| `volume` | Volume |
| `adjusted` | Prix ajusté (éliminé avant insertion, `05_pricediv.R:55`) |

### `dividendes`
Historique des dividendes, un row par `(symbol, date)`. Source : FMP
(`dividends-calendar` pour les présents, `dividends` par compagnie pour les
absents). Colonnes utilisées : `symbol`, `date`, `adjdividend`, `frequency`
(Quarterly / Semi-Annual / Annual / Monthly / Weekly / Special / Irregular).

### `split_log`
Journal des splits détectés, un row par `(symbol, split_date)` (unique).

| Colonne | Description |
|---|---|
| `symbol` | Ticker |
| `split_date` | Date du split |
| `split_ratio` | Ratio du split |
| `status` | `pending` / `confirmed` / `failed` |
| `detected_date` | Date de détection |
| `confirmed_date` | Date de confirmation |
| `rewrite_date` | Date de réécriture |
| `notes` | Notes (ex: message d'erreur) |

Source : `02_splits.R`, `2-cron_split_fcts.R`.

### `cron_log`
Résumé d'un run du cron, un row par `run_id`. Schéma explicite dans
`0-api_fcts.R:129-141`.

| Colonne | Type | Description |
|---|---|---|
| `run_id` | BIGSERIAL PK | Identifiant du run |
| `run_date` | DATE | Date du run |
| `statut` | TEXT | `OK` / `ERROR` / `WARN` |
| `nb_ok` | INTEGER | Nombre d'étapes OK |
| `nb_warn` | INTEGER | Nombre d'avertissements |
| `nb_err` | INTEGER | Nombre d'erreurs |
| `message` | TEXT | Message de synthèse |
| `started_at` | TIMESTAMP | Début du run |
| `finished_at` | TIMESTAMP | Fin du run |

---

## Tables `_build` (transformées)

### `cies_profile_build`
Profil nettoyé, un row par `symbol`. Reconstruite à chaque run depuis
`cies_profile_orig` (`01_profiles.R:158`). Colonnes : `symbol`, `companyname`,
`currency`, `cik`, `cusip`, `exchange`, `industry`, `website`, `description`,
`sector`, `image`, `last_updated`.

### `financial_stmts_build`
États financiers **normalisés en TTM** (trailing 12 mois), un row par
`(symbol, date)`. Reconstruite par `tidy_stmts2()` (`7-cron_tidy_stmts2_fcts.R`).

- Colonnes générales : `date`, `symbol`, `reportedcurrency`, `cik`, `filingdate`,
  `accepteddate`, `fiscalyear`, `period` (normalisé `Q4 → FY`).
- Colonnes income prefixées `is_` : `is_revenue`, `is_grossprofit`,
  `is_interestincome`, `is_interestexpense`, `is_depreciationandamortization`,
  `is_ebitda`, `is_ebit`, `is_operatingincome`, `is_netincome`, `is_eps`,
  `is_epsdiluted`, `is_weightedaverageshsout`, `is_weightedaverageshsoutdil`.
- Colonnes balance prefixées `bs_` : `bs_totalcurrentassets`,
  `bs_totalnoncurrentassets`, `bs_totalassets`, `bs_totalcurrentliabilities`,
  `bs_totalnoncurrentliabilities`, `bs_totalliabilities`,
  `bs_totalstockholdersequity`, `bs_shorttermdebt`, `bs_longtermdebt`,
  `bs_totaldebt`.
- Colonnes cash flow prefixées `cf_` : `cf_stockbasedcompensation`,
  `cf_netcashprovidedbyoperatingactivities`, `cf_netcashprovidedbyinvestingactivities`,
  `cf_netcashprovidedbyfinancingactivities`, `cf_freecashflow`.
- Colonnes calculées : `caf` (= `is_netincome + is_depreciationandamortization
  + cf_stockbasedcompensation`), `m_brut`, `m_ebitda`, `m_net` (marges).

### `valuation_build`
Bandes de valorisation boursière, un row par `(symbol, date)`. Reconstruite par
`valuation_stockprice2()` (`8-cron_ratios2_fcts.R`). Fenêtre glissante
`window_months = 18` (≈ `n_days = 378` jours ouvrés).

| Colonne | Description |
|---|---|
| `symbol` | Ticker |
| `date` | Date |
| `close` | Prix de clôture |
| `buy_p_to_s`, `sell_p_to_s`, `caution_p_to_s` | Bandes P/S |
| `buy_p_to_ebitda`, `sell_p_to_ebitda`, `caution_p_to_ebitda` | Bandes P/EBITDA |
| `buy_pe`, `sell_pe`, `caution_pe` | Bandes P/E |
| `buy_pe_dil`, `sell_pe_dil`, `caution_pe_dil` | Bandes P/E dilué |

Bandes **en prix** = ratio min/max sur fenêtre × par-share courant. `caution` =
moyenne de `buy` et `sell`.

### `cagr_price_build`
CAGR du prix, un row par `symbol`. Reconstruite par `cagr_stockprice2()`
(`8-cron_ratios2_fcts.R`, `years = c(1, 3, 5, 10)`). Colonnes : `symbol`, `date`,
`close`, `cagr_1y`, `cagr_3y`, `cagr_5y`, `cagr_10y`.

### `cagr_stmts_build`
CAGR des états financiers, un row par `symbol` (dernière ligne). Reconstruite
par `cagr_stmts2()` (`8-cron_ratios2_fcts.R`, `cols` listées au
`8-cron_ratios2_fcts.R:255`). Colonnes : `date`, `symbol`, `period`, les
colonnes brutes concernées, puis `cagr_1_<col>`, `cagr_3_<col>`, `cagr_5_<col>`,
`cagr_10_<col>`.

### `dividendes_build`
Métriques de dividendes par `symbol`. Reconstruite par
`build_dividendes_build2()` (`9-cron_dividendbuild2_fcts.R`). Colonnes :
`symbol`, `last_updated`, `last_div_date`, `div_ttm`, `div_forward`,
`croissance_reguliere`, `close_ref`, `yield`, `cagr_div_1a`, `cagr_div_3a`,
`cagr_div_5a`, `cagr_div_10a`, `fcf_payout`, `fcf_coverage`, `has_special`,
`has_irregular`, `last_special_date`, `last_irregular_date`.

### `quality_build`
Ratios de qualité et de valorisation, un row par `symbol` (instantané).
Reconstruite par `build_quality_build2()` (`10-cron_quality_build2.R`).
Colonnes : `symbol`, `last_updated`, `sector`, `industry`, `period`,
`date_stmts`, `filingdate`, `roa`, `roe`, `roa_moy5`, `roe_moy5`, `m_brut`,
`m_ebitda`, `m_net`, `fcf_rev`, `ratio_courant`, `couv_interet`, `d_actif`,
`pppi`, `close`, `mktcap_m`, `p_to_s_calc`, `p_to_ebd_calc`, `pe_calc`,
`peg_calc`, `r_pts`, `r_ebd`, `r_pe`, `r_ped`, `ratio_moyen`.

---

## Fichiers de suivi sur S3

- `stockToolsR/data/cies_order.rds` : suivi des publications (mardis), statuts
  `inc_status` / `bs_status` / `cf_status` (`pending` / `complete`), champ
  `reportDate` / `reportDate_mod` (`03_earning_cal.R`, `04_statements.R`).
- `stockToolsR/data/non_available_stockprice.rds` : tickers non disponibles sur
  Yahoo Finance (`05_pricediv.R:26`).
- `stockToolsR/logs/YYYY-MM-DD.rds` : détail journalier du log du cron
  (`1-log_fcts.R`, `log_get_detail`). Colonnes : `etape`, `statut`, `symbol`,
  `message`.

---

## Relations principales

```
cies_profile_orig ──► cies_profile_build          (mapping symbol → sector/industry)
qts_*_stmts_orig ─┐
fy_*_stmts_orig  ─┴─► financial_stmts_build       (TTM normalisé)
stockprice ─────────► valuation_build / cagr_price_build
financial_stmts_build ─► cagr_stmts_build
dividendes ──────────► dividendes_build (via valuation_build close, financial_stmts_build FCF)
financial_stmts_build + valuation_build + cagr_stmts_build + cies_profile_build
    ──► quality_build
```

---

## Piste à venir

- **Valorisation sectorielle** : voir `inst/script2/10_secteur_val.R` (prototype
  n'écrivant pas en base). Si le résultat est validé, création probable d'une
  table `sector_valuation_build` dédiée.
- Centraliser les schémas SQL (`inst/sql/create_tables.sql`) — voir ROADMAP.