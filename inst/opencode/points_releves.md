# Points relevés — stockToolsR

Notes de vérification et incohérences détectées durant le développement.
Chaque entrée est datée et référencée (fichier + ligne).

---

## 2026-10-01 — `01_profiles.R`

- **Incohérence 1a vs 1b** (`01_profiles.R:113-117`) : `cies_in_db` lit tous
  les symboles de `cies_profile_orig` **sans** filtre `symbol %in% tickers`,
  alors que 1b (`:137-143`) filtre bien sur `tickers`. Le diff
  `setdiff(tickers, cies_in_db)` inclut donc les tickers non-S&P 500 présents
  en base. Mineur en pratique.
- **Risque de doublon** (`01_profiles.R:87-103`) : si `upsert_profile` est
  appelé avec `force = FALSE` sur une ligne déjà existante, aucun contrôle
  d'unicité n'est fait avant l'INSERT simple (`append = TRUE`) → doublon
  possible. Le flot nominal (1a sur manquants) évite ce cas, mais sans
  garantie stricte.
- **Par design** : un échec `upsert_profile` (retour `FALSE`) ne bloque pas la
  boucle — les erreurs API sont loggées puis le run continue.

---

## 2026-10-01 — Structure réelle `cies_profile_orig`

Table peuplée (1 818 lignes, S&P 500 + suivis) exposant **37 colonnes**, dont
beaucoup ne sont **pas** conservées dans la reconstruction `_build`. Seules
11 colonnes sont retenues pour `cies_profile_build` (`01_profiles.R:159-160`) :
`symbol, companyname, currency, cik, cusip, exchange, industry, website,
description, sector, image, last_updated` (12 en comptant `last_updated`).

Le profil FMP brut offre des champs riches, actuellement non exploités par le
pipeline :
- **Position de marché** : `price`, `marketcap`, `beta`, `range` (52 sem.),
  `change`, `changepercentage`, `volume`, `averagevolume`.
- **Dividende** : `lastdividend`.
- **Identité** : `isin`, `exchangefullname`, `country`, `ceo`.
- **Employeur** : `fulltimeemployees`.
- **Contact** : `phone`, `address`, `city`, `state`, `zip`.
- **Méta** : `ipodate` (date d'introduction), `defaultimage`.
- **Drapeaux** (`lgl`) : `isetf`, `isactivelytrading`, `isadr`, `isfund`.

### Structure de la table `_build` (12 colonnes)

`symbol, companyname, currency, cik, cusip, exchange, industry, website,
description, sector, image, last_updated` — soit la **projection** de la
`_orig` réduite au strict nécessaire (ex: le pipeline n'a besoin que de
`symbol` → `sector`/`industry` pour joindre dans `quality_build`).

### Principe `_orig` vs `_build`

La `_build` est **écrasée à chaque run** (overwrite). C'est une table
« utilitaire » volontairement légère pour travailler vite — on ne garde que ce
dont le pipeline a besoin. Pour `cies_profile`, la pertinence est faible (les
colonnes omises ne servent pas), mais cette logique prend tout son sens pour
les tables volumineuses (séries temporelles : seuls les champs utilisés par les
ratios sont conservés, allégeant nettement les requêtes).

Les champs exclus ne sont **pas perdus** : ils restent disponibles dans la
`_orig`, source de vérité brute. Si une future idée a besoin d'un champ exclu,
il faut l'ajouter à la projection `_build` (ou lire directement la `_orig`).

### Opportunités d'utilisation (pour évaluation future)

- `lastdividend` + `ipodate` : croisement avec `dividendes_build`.
- `marketcap` : déjà recalculé dans `quality_build` (`mktcap_m`), mais dispo
  ici à l'état brut quotidien.
- Drapeaux `isetf` / `isfund` / `isadr` : filtres potentiels pour exclure
  certains titres.
- `range` / `beta` / `averagevolume` : indicateurs de risque/liquidité.
- `isin`, `exchangefullname`, `fulltimeemployees`, `country` : enrichissement
  de métadonnées pour l'app Shiny.
- Pour exploiter ces champs dans les tables dérivées, les **ajouter à la
  projection `_build`** au besoin (voir `01_profiles.R:159-160`).

---

## 2026-10-01 — Structure réelle `split_log`

Table peuplée (9 lignes à la consultation) exposant **9 colonnes**. Champs :
`id` (INT), `symbol`, `split_date` (DATE), `split_ratio` (DOUBLE),
`status`, `detected_date`, `confirmed_date`, `rewrite_date`, `notes`.

Détails :
- `id` : séquence INT (pas BIGSERIAL) — PK.
- `split_ratio` : peut être >1 (split 1→25, 1→10) ou <1 (inverse split :
  `0.333` = 3:1, `0.5` = 2:1) — valeurs `DD` et `HON` en reverse split.
- `status` : `confirmed` majoritaire ; l'exemple montre `PSKY` avec
  `confirmed_date`/`rewrite_date` = NA → encore `pending` ou `failed` (ligne
  détectée 2026-10, non encore traitée car date non passée).
- `notes` : "Nettoyage effectué via cron" pour les `confirmed`.

### Observations utiles

- Les **reverse splits** (`ratio < 1`, ex: DD, HON) sont bien gérés — la
  suppression + re-téléchargement s'applique de la même façon.
- `PSKY` (detected 2026-10, split non encore confirmé) illustre le délai
  entre détection (mardi) et traitement (date passée) — cohérent avec
  `get_pending_splits(horizon_days = -1)`.

---

## 2026-10-01 — `03_earning_cal.R`

- **Fenêtre `-5/+15` jours** : adaptée à un cron quotidien, mais un arrêt
  prolongé peut faire manquer des publications (jamais rattrapées ensuite).
  Déjà noté dans ROADMAP (`-2 mois/+1 mois` à évaluer).
- **Idempotence partielle** : `update_cies_order()` n'ajoute que les nouvelles
  compagnies — une compagnie déjà présente ne voit pas sa date de publication
  mise à jour si elle change.
- **Fonction legacy `fmp_get_earnings_calendar()`**
  (`R/3-cron_earning_cal_fcts.R`) : clé API **dans l'URL** (risque de fuite
  dans les logs) + endpoint codé en dur. **Non appelée** par le script révisé
  (qui utilise `fmp_get()` par header). **Supprimée** (2026-10-01).

### Structure réelle `cies_order.rds` (S3, 103 lignes)

Le fichier suit **103 compagnies** avec 6 colonnes :

| Colonne | Type | Description |
|---|---|---|
| `symbol` | chr | Ticker |
| `reportDate` | date | Date annoncée de publication |
| `reportDate_mod` | date | Date modifiée (rattrapée si décalage) |
| `inc_status` | chr | Statut income — `pending` / `incomplete` / `complete` |
| `bs_status` | chr | Statut balance |
| `cf_status` | chr | Statut cash flow |

### Écart constaté avec la doc du script

Le script (`03_earning_cal.R` + `init_cies_order()`) initialise les statuts à
`"pending"` **seulement**. Or les données réelles montrent une **3ᵉ valeur
`"incomplete"`** (ex: CTRA, AVB, JPM → `incomplete` ; EA, JNJ → `pending`).
La valeur `incomplete` est écrite par l'étape 4 (`04_statements.R`).

### Cycle de vie d'un statut (résolu)

Confirmé par la lecture de `04_statements.R` + `check_filing_exists()` :
- `03` initialise les statuts à **`pending`** ;
- `04` (vérification) fait passer chaque état à **`incomplete`** (filing pas
  encore trouvé dans la fenêtre ±7 j autour de `reportDate`) ou **`complete`**
  (filing retrouvé) ;
- `incomplete` → `reportDate_mod = Sys.Date() + 3` (retry dans 3 jours) ;
- `complete` sur les 3 états → la compagnie est **retirée** de `cies_order`.

Les fichiers présents montrent donc des compagnies en attente (`pending`) et
d'autres déjà vérifiées mais non complètes (`incomplete`), selon leur position
dans le cycle.

### Observations

- `reportDate_mod ≠ reportDate` pour certaines lignes (ex: AVB 04-29→07-16,
  JPM 04-14→10-02) : la date modifiée sert à rattraper un décalage de
  publication.
- Seules 103 compagnies suivies sur ~500 tickers S&P 500 : correspond aux
  publications en cours / à venir dans la fenêtre.

---

## 2026-10-01 — Structure réelle des tables d'états financiers `_orig`

Les 6 tables `*_stmts_orig` (qts + fy, pour income / balance / cash-flow) ont
la **même structure : 39 colonnes** (le FMP renvoie l'income-statement
complet). Exemples de volumes : `fy_income_stmts_orig` = 5 285 lignes,
`qts_income_stmts_orig` = 21 569 lignes (les tables trimestrielles sont ~4×
plus volumineuses).

### Colonnes communes (toutes tables)

`symbol`, `date`, `reportedcurrency`, `cik`, `filingdate`, `accepteddate`
(dttm), `fiscalyear`, `period` (Q1–Q4 / FY).

### Income (extrait des colonnes métier)

`revenue`, `costofrevenue`, `grossprofit`, `researchanddevelopmentexpenses`,
`generalandadministrativeexpenses`, `sellingandmarketingexpenses`,
`sellinggeneralandadministrativeexpenses`, `otherexpenses`,
`operatingexpenses`, `costandexpenses`, `netinterestincome`, `interestincome`,
`interestexpense`, `depreciationandamortization`, `ebitda`, `ebit`,
`nonoperatingincomeexcludinginterest`, `operatingincome`,
`totalotherincomeexpensesnet`, `incomebeforetax`, `incometaxexpense`,
`netincomefromcontinuingoperations`, `netincomefromdiscontinuedoperations`,
`otheradjustmentstonetincome`, `netincome`, `netincomedeductions`,
`bottomlinenetincome`, `eps`, `epsdiluted`, `weightedaverageshsout`,
`weightedaverageshsoutdil`.

### Observations / écarts avec la doc

- La table **brute** expose **39 colonnes** (income complet) alors que
  `06_tidy_stmts.R` n'en conserve qu'un **sous-ensemble** dans
  `financial_stmts_build` (voir architecture.md). Illustration du principe
  `_orig` = source de vérité riche, `_build` = projection légère.
- **Nuances comptables** : `netincome ≠ bottomlinenetincome` pour certains
  titres (ex: INVH `netincome = 587924000` vs `bottomlinenetincome =
  586964000` — différence due à `netincomedeductions`). Idem pour NVDA
  (`otheradjustmentstonetincome`). Le choix de colonnes dans la `_build` doit
  donc être explicite sur *quelle* mesure de net income est utilisée.
- `period = "Q1"`/`"Q2"`… dans `qts_*` ; `period = "FY"` dans `fy_*` — la
  table `qts_*` ne contient que des trimestres, `fy_*` que des annuels (pas de
  mélange).
- `accepteddate` est un TIMESTAMP (dttm), contrairement aux autres dates
  (DATE).

---

## 2026-10-01 — Structure réelle des tables **balance** `_orig`

Les tables `*_balance_stmts_orig` (fy + qts) ont **61 colonnes** (le
balance-sheet FMP complet). Volumes : `fy_balance_stmts_orig` = 5 271 lignes,
`qts_balance_stmts_orig` = 21 396 lignes.

### Colonnes communes (comme income)

`symbol`, `date`, `reportedcurrency`, `cik`, `filingdate`, `accepteddate`,
`fiscalyear`, `period`.

### Colonnes Actifs

`cashandcashequivalents`, `shortterminvestments`, `cashandshortterminvestments`,
`netreceivables`, `accountsreceivables`, `otherreceivables`, `inventory`,
`prepaids`, `othercurrentassets`, `totalcurrentassets`,
`propertyplantequipmentnet`, `goodwill`, `intangibleassets`,
`goodwillandintangibleassets`, `longterminvestments`, `taxassets`,
`othernoncurrentassets`, `totalnoncurrentassets`, `otherassets`, `totalassets`.

### Colonnes Passifs

`totalpayables`, `accountpayables`, `otherpayables`, `accruedexpenses`,
`shorttermdebt`, `capitalleaseobligationscurrent`, `taxpayables`,
`deferredrevenue`, `othercurrentliabilities`, `totalcurrentliabilities`,
`longtermdebt`, `capitalleaseobligationsnoncurrent`,
`deferredrevenuenoncurrent`, `deferredtaxliabilitiesnoncurrent`,
`othernoncurrentliabilities`, `totalnoncurrentliabilities`, `otherliabilities`,
`capitalleaseobligations`, `totalliabilities`.

### Colonnes Capitaux propres

`treasurystock`, `preferredstock`, `commonstock`, `retainedearnings`,
`additionalpaidincapital`, `accumulatedothercomprehensiveincomeloss`,
`othertotalstockholdersequity`, `totalstockholdersequity`, `totalequity`,
`minorityinterest`.

### Colonnes Totaux / agrégats

`totalliabilitiesandtotalequity`, `totalinvestments`, `totaldebt`, `netdebt`.

### Observations

- **`totaldebt` / `netdebt` déjà calculés par FMP** : disponibles directement
  (cf. `shorttermdebt` + `longtermdebt`, `netdebt = totaldebt - cash`).
- **Balance parfois « anormale »** : ex. MTD `totalstockholdersequity` =
  **négatif** (`-23636000`, `-126890000`) — sociétés en capitaux propres
  négatifs. `totalassets` reste cohérent avec
  `totalliabilitiesandtotalequity` (identiques pour MTD).
- `treasurystock` est **négatif** (déduction classique).
- `fiscalyear` peut **décaler** vs `date` : ex. NVDA date 2022-05-01 →
  `fiscalyear = "2023"` (exercice fiscal décalé, FY mai→avril).
- `qts_*` : dates trimestrielles (ex: NVDA 2022-05-01 = Q1 FY2023).

---

## 2026-10-01 — Structure réelle des tables **cash-flow** `_orig`

Les tables `*_cf_stmts_orig` (fy + qts) ont **47 colonnes** (le cash-flow FMP
complet). Volumes : `fy_cf_stmts_orig` = 5 282 lignes,
`qts_cf_stmts_orig` = 21 504 lignes.

### Colonnes communes (comme income/balance)

`symbol`, `date`, `reportedcurrency`, `cik`, `filingdate`, `accepteddate`,
`fiscalyear`, `period`.

### Flux d'exploitation

`netincome`, `depreciationandamortization`, `deferredincometax`,
`stockbasedcompensation`, `changeinworkingcapital`, `accountsreceivables`,
`inventory`, `accountspayables`, `otherworkingcapital`, `othernoncashitems`,
`netcashprovidedbyoperatingactivities`.

### Flux d'investissement

`investmentsinpropertyplantandequipment`, `acquisitionsnet`,
`purchasesofinvestments`, `salesmaturitiesofinvestments`,
`otherinvestingactivities`, `netcashprovidedbyinvestingactivities`.

### Flux de financement

`netdebtissuance`, `longtermnetdebtissuance`, `shorttermnetdebtissuance`,
`netstockissuance`, `netcommonstockissuance`, `commonstockissuance`,
`commonstockrepurchased`, `netpreferredstockissuance`, `netdividendspaid`,
`commondividendspaid`, `preferreddividendspaid`, `otherfinancingactivities`,
`netcashprovidedbyfinancingactivities`.

### Soldes / agrégats

`effectofforexchangesoncash`, `netchangeincash`, `cashatendofperiod`,
`cashatbeginningofperiod`, `operatingcashflow`, `capitalexpenditure`,
`freecashflow`, `incometaxespaid`, `interestpaid`.

### Observations

- **`freecashflow` déjà calculé par FMP** (= `operatingcashflow` +
  `capitalexpenditure`), ainsi que `operatingcashflow` (alias de
  `netcashprovidedbyoperatingactivities`) et `capitalexpenditure` (alias de
  `investmentsinpropertyplantandequipment` avec signe inversé).
- **Signe des Capex** : `investmentsinpropertyplantandequipment` et
  `capitalexpenditure` sont **négatifs** (dépenses).
- `netdividendspaid`/`commondividendspaid` **négatifs** (versements).
- `netdebtissuance` = `longtermnetdebtissuance` + `shorttermnetdebtissuance`.
- `incometaxespaid` et `interestpaid` souvent **0 sur les trimestres**
  (`qts_*`) pour certains titres, parfois renseignés en `fy_*` — valeurs
  sujettes à incomplétude selon les compagnies.
- `changeinworkingcapital` est déjà le détail consolidé de
  `accountsreceivables`/`inventory`/`accountspayables`/`otherworkingcapital`.

### Synthèse des 3 familles `_stmts_orig`

| Famille | Nb colonnes | fy (lignes) | qts (lignes) |
|---|---|---|---|
| income | 39 | 5 285 | 21 569 |
| balance | 61 | 5 271 | 21 396 |
| cash-flow | 47 | 5 282 | 21 504 |

Chaque table partage les 8 colonnes communes (`symbol`, `date`,
`reportedcurrency`, `cik`, `filingdate`, `accepteddate`, `fiscalyear`,
`period`). Les `qts_*` sont ~4× plus volumineuses que les `fy_*`.

---

## 2026-10-01 — `05_pricediv.R` — fonctions legacy dividendes

Dans `R/5-cron_pricediv_fcts.R`, les fonctions **non appelées** par le script
révisé (il appelle directement `fmp_get()`) :

- ~~`update_dividendes()`~~ — **supprimée** (2026-10-01).
- ~~`fmp_dividends_company_get()`~~ — **supprimée** (2026-10-01).
- ~~`fmp_dividends_calendar_get()`~~ — **supprimée** (2026-10-01).

`R/5-cron_pricediv_fcts.R` ne contient donc plus que `update_stockprice()`
(l'unique fonction utilisée par le script 05).

---

## 2026-10-01 — `tidy_stmts2()` — risques potentiels (pas traités)

Discussion sur `R/7-cron_tidy_stmts2_fcts.R` (reconstruction
`financial_stmts_build` en TTM). Les données actuelles semblent correctes,
**aucune correction apportée pour l'instant**.

- **Trimestre manquant (gap) → TTM faussé** : `slider::slide_sum(before = 3,
  complete = TRUE)` somme les **3 lignes physiques précédentes**, pas les
  trimestres calendaires. Si un symbol a un trimestre manquant, la « somme de
  4 lignes » couvre plus de 4 trimestres de temps → ce n'est plus la somme de
  4 trimestres consécutifs. À traiter si des gaps apparaissent (compagnies
  récentes, données manquantes). Pour l'instant, données propres (S&P 500).

- **[HAUTE IMPORTANCE] Filtre `period == period_ref` dans `tidy_stmts2()`
  (`7-cron_tidy_stmts2_fcts.R:172-183`)** : mélange de deux idées qui n'ont
  pas la même finalité.
  - **Idée A — période homogène pour comparaison** : ne garder qu'une seule
    `period` par symbol (ex: croissance 1/3/5/10 ans sur des points de même
    nature). Nécessite une période unique.
  - **Idée B — valuation la plus récente** : garder **tous les trimestres
    TTM** pour avoir un ratio (ex: P/S) le plus récent possible à comparer
    aux prix quotidiens. Nécessite la série TTM glissante complète.
  - Le filtre actuel (`period == period_ref`, period de la ligne la plus
    récente) ne satisfait ni A ni B correctement : il élimine la plupart des
    points et casse la glissante TTM (si la dernière ligne est un Q1, on jette
    Q2/Q3/FY ; si c'est un FY, on jette tout le trimestriel → 1 point/an).
  ### Conséquence concrète sur l'étape 07 (les deux besoins s'opposent)

Le filtre `period == period_ref` (FY-only dans les données observées) bride
deux étapes 07 aux besoins **opposés** :
- **`valuation_stockprice2`** veut la série TTM glissante **complète**
  (trimestres) : avec FY-only, `tidyr::fill(.direction="up")` fige les ratios
  P/S, P/EBITDA, P/E **pendant toute l'année** jusqu'à la publication suivante
  → bande de valorisation **stalée** (idée B non servie).
- **`cagr_stmts2`** veut une période **homogène** (FY vs FY, Q1 vs Q1) : la
  granularité annuelle est **cohérente** ici (idée A). Les NA sur
  `cagr_5/10_*` viennent en partie du manque de profondeur (1 point/an → il
  faut 5/10 ans de données).

### Proposition (à valider plus tard — PAS de correction maintenant)

- **Enlever le filtre `period == period_ref` de `tidy_stmts2()`** →
  `financial_stmts_build` garde la série TTM glissante complète (source riche,
  sert l'idée B de `valuation_stockprice2`).
- **Ré-appliquer le filtre `period == period_ref` juste avant `cagr_stmts2`**
  → chaque étape 07 choisit sa granularité, sans choix forcé en amont.
- Impact à vérifier : remettre les trimestres augmente le volume de
  `financial_stmts_build` (~4× les lignes) → vérifier que `valuation_build`,
  `cagr_stmts_build` et les étapes 08/09 n'en sont pas affectées négativement.

---

## 2026-10-01 — `dividendes_build` (`08_divbuild.R`)

### [IMPORTANT] CAGR basé sur la position (nombre de lignes) — à corriger

Dans `.calc_div_symbol()` (`9-cron_dividendbuild2_fcts.R:68-80`), `annual_at()`
compte **`n` lignes consécutives** pour reconstruire une « année » de
dividendes. Si un versement est **suspendu / manquant** (beaucoup plus probable
qu'un état financier manquant), 4 lignes ne couvrent plus 1 an mais ~1 an + 1
trimestre → la somme annuelle (et donc les CAGR 1/3/5/10 ans) est **faussée**.

Préférence : **`div_ttm`, basé sur les dates** (fenêtre 12 mois calendaires,
`date >= max_date - 1 an`), est la bonne approche. Le CAGR basé sur la position
devra être corrigé pour utiliser une logique calendaire similaire (sommer les
versements dans des fenêtres annuelles par date, pas par nombre de lignes).

### [IMPORTANT] Dépendance de 08 à 06/07

`dividendes_build` emprunte :
- `close_ref` (dernier prix) depuis **`valuation_build`** (07) ;
- `cf_freecashflow` et `is_weightedaverageshsout` depuis
  **`financial_stmts_build`** (06).

→ `yield` et `fcf_payout`/`fcf_coverage` dépendent de la granularité de 06
(le filtre `period_ref`). Tout changement de 06 se répercute ici.

### Structure réelle `dividendes_build`

**418 lignes** (compagnies avec dividendes), **18 colonnes** : `symbol`,
`last_updated`, `last_div_date`, `div_ttm`, `div_forward`,
`croissance_reguliere` (lgl), `close_ref`, `yield`, `cagr_div_1a/3a/5a/10a`,
`has_special`, `has_irregular` (lgl), `last_special_date`,
`last_irregular_date`, `fcf_payout`, `fcf_coverage`.

Observations :
- `yield` en fraction (0.0076 ≈ 0.76%).
- Des compagnies sans dividende (`div_ttm` = NA, ex: ACGL) sont présentes
  (probablement `lastdividend > 0` dans le profil mais TTM vide).
- `fcf_coverage = 1/fcf_payout` (cohérent).

---

## 2026-10-01 — `09_quality.R` — points de vigilance [TRÈS IMPORTANT]

À réviser en premier sur `build_quality_build2()`
(`R/10-cron_quality_build2.R`) :

1. **ROE / `roa_moy5` / `roe_moy5`** : pas de guard sur
   `bs_totalstockholdersequity` **négatif** (observé : MTD) → ROE faussé ou
   explosé. Les autres ratios (ex: `couv_interet`) ont un guard `> 0`, pas
   ceux-ci.
2. **`couv_interet`** : guard sur `interestexpense > 0`, mais **pas sur `ebit`**
   → un EBIT négatif donne une couverture négative.
3. **`peg_calc`** : `pe_calc / (cagr_3_is_epsdiluted × 100)` — dépend du CAGR
   EPS 3 ans de 07 (donc du filtre `period_ref`), guard `> 0`.
4. **`r_*` (position dans la bande)** : `(close - buy)/(sell - buy)` — suppose
   `sell > buy`, sinon NA.
5. **`stmts_moy5`** : « 5 dernières périodes » change de sens selon la
   granularité de 06 (5 ans vs 5 trimestres) — même sensibilité que 08.

### Corrections décidées — `09_quality.R` (à implémenter)

Décisions de l'utilisateur, validées le 2026-10-01 :

1. **ROE / ROA (et moyennes)** : mettre à **NA** si `bs_totalstockholdersequity`
   est **négatif** (et/ou si le ratio `R` résultant est négatif / absurde).
2. **`couv_interet`** : mettre à **NA** si `is_ebit` est **négatif**.
3. **`peg_calc`** : garde-fou déjà en place (`cagr_3_is_epsdiluted > 0`),
   rien à changer — à revérifier seulement.
4. **`r_*` (position bande)** : **clôturé** (2026-10-01). Une bande **inversée
   (`sell < buy`) est impossible** par construction (`min_ratio ≤ max_ratio`
   × même `per_share`). Seul cas réel : bande **nulle** (`sell == buy`, fenêtre
   à valeur unique) → le garde-fou `> 0` renvoie NA, comportement correct.
   Rien à corriger. Note : une bande **étroite** (buy/sell proches) donne un
   signal `r_*` faible (peu de marge de profit estimée) — propriété, pas bug.
5. **`stmts_moy5`** : **Option A retenue** — prendre une ligne par exercice
   (lignes 1, 5, 9, 13, 17 sur une série trimestrielle) pour une moyenne
   **annuelle**, et ne pas mélanger les périodes différentes. Suppose une
   série trimestrielle régulière.

   **→ REMPLACÉE (2026-10-01) par une meilleure approche** : pour la moyenne
   ROA/ROE 5 ans, prendre la **même période que la ligne la plus récente** de
   chaque symbol (si le plus récent est Q3 → les 5 derniers Q3 ; si FY → les 5
   derniers FY). Moyenner **jusqu'à 5** occurrences de cette période, et
   retourner **NA si moins de 3 valeurs** disponibles. Plus robuste que
   l'Option A (s'affranchit des trous entre trimestres) et ne mélange pas les
   périodes.

### Structure réelle `quality_build`

(à compléter — l'utilisateur devait fournir la structure ; table finale de
synthèse, 1 row par symbol, 5 sources jointes.)

---

## 2026-10-01 — Structures réelles des tables `_build` (06 & 07)

### `financial_stmts_build` (produite par 06)

5 282 lignes, **40 colonnes**. Ordre : `date`, `symbol`, `reportedcurrency`,
`cik`, `filingdate`, `accepteddate` (dttm), `fiscalyear` (**dbl**),
`period` (**"FY" uniquement** ici → effet du filtre `period == period_ref`),
puis les préfixes `is_` (13), `bs_` (10), `cf_` (5), et calculées `caf`,
`m_brut`, `m_ebitda`, `m_net`.

Observation : dans l'exemple, **`period` = "FY" pour toutes les lignes** de A et
AAPL (et `date` annuelle 10-31 / 09-27) → confirme le problème 5 : la série est
réduite à 1 point par an (granularité annuelle), la glissante TTM trimestrielle
est perdue.

### `valuation_build` (produite par 07)

**1 129 205 lignes** (≈ 500 tickers × ~2250 jours), **15 colonnes** :
`symbol`, `date`, `close`, puis pour chaque ratio (P/S, P/EBITDA, P/E, P/E
dilué) les 3 bandes `buy_`, `sell_`, `caution_`. Table **beaucoup plus
volumineuse** que les autres `_build` (série temporelle quotidienne).

### `cagr_price_build` (produite par 07)

**503 lignes** (un row par symbol), **7 colonnes** : `symbol`, `date`, `close`,
`cagr_1y`, `cagr_3y`, `cagr_5y`, `cagr_10y`. 1 ligne par ticker, date = dernier
jour de prix.

### `cagr_stmts_build` (produite par 07)

**503 lignes** (un row par symbol), **53 colonnes** : `symbol`, `date`,
`period`, les 10 colonnes brutes (`is_revenue`...`caf`), puis les `cagr_N_<col>`
(1/3/5/10 ans). Observation : beaucoup de `NA` sur les horizons longs
(`cagr_5/10`) — compagnies avec moins de données historiques (IPO récente, ou
`financial_stmts_build` limité par le filtre `period_ref` à 1 point/an → pas
assez de points pour `lag(5)`/`lag(10)`).

Même schéma que `fmp_get_earnings_calendar()` de l'étape 3 : candidates à
suppression (le helper `fmp_get()` les a remplacées).

### Observations delta prix

- `update_stockprice()` télécharge depuis `min(last_date)` **global** sur les
  tickers existants (une seule date de départ pour tous) puis élimine les
  doublons par anti-join — pas un delta par ticker. Peut récupérer plus de
  données que nécessaire, mais reste correct après filtre.
- `update_stockprice()` élimine la **date du jour** (`filter(date !=
  to_date)`) — n'insère que des journées de marché complètes.

---

## 2026-10-01 — Structure réelle `dividendes`

Table peuplée (**49 479 lignes**) exposant **9 colonnes** :

| Colonne | Type | Description |
|---|---|---|
| `symbol` | chr | Ticker |
| `date` | date | Date du dividende (ex-dividend date) |
| `recorddate` | chr | Date d'enregistrement |
| `paymentdate` | chr | Date de paiement |
| `declarationdate` | chr | Date de déclaration |
| `adjdividend` | dbl | Dividende ajusté (splits) |
| `dividend` | dbl | Dividende nominal |
| `yield` | dbl | Rendement (0.27 ≈ 0.27%) |
| `frequency` | chr | Quarterly / Semi-Annual / Annual / ... |

### Observations

- **Types de dates incohérents** : `date` est un `date`, mais
  `recorddate`/`paymentdate`/`declarationdate` sont des **`chr`** (format
  ISO "YYYY-MM-DD"). À convertir en `date` pour des calculs fiables.
- **`adjdividend` vs `dividend`** : peuvent différer (ex: AVGO 0.65 vs 5.25
  sur l'ancien split) — `adjdividend` est ajusté pour les splits, `dividend`
  est le montant nominal. Le pipeline utilise probablement `adjdividend`.
- **`yield`** stocké en fraction (0.274 = 0.27%) — attention à l'échelle si
  comparé à un yield en pourcentage.
- **49 479 lignes** pour ~500 tickers → ~100 dividendes/compagnie en
  moyenne (12 ans), cohérent avec l'import `limit = 500` par compagnie.
- GOOGL/AVGO versent désormais des dividendes (périodes récentes 2025-2026)
  — cohérent avec `lastdividend > 0` dans `cies_profile_orig`.