# =============================================================================
# 0-plan.R — Point d'entrée du cron quotidien (version révisée, script2)
# Exécution : Rscript inst/script2/0-plan.R
# =============================================================================
# En local : tunnel SSH pour accéder au PostgreSQL du VPS
#   ssh -L 5432:127.0.0.1:5432 hugo@158.69.221.155

library(here)
library(DBI)
library(RPostgres)
library(dplyr)
library(dbplyr)
library(s3db)
library(lubridate)
library(devtools)
library(stringr)
library(BatchGetSymbols)

# Charge le package (pour d'éventuelles fonctions dans R/ à réutiliser)
devtools::load_all()

# ---------------------------------------------------------------------------
# Connexion S3 (protegR2) + config globale
# ---------------------------------------------------------------------------
s3_connection_HL()
config_global <- s3db::s3readRDS_HL(object = "config_files/config_global.rds")

# Clé API FMP — depuis config_global (protegR2), jamais en dur
key_fmp_api <- config_global$stockToolsR$key_fmp_api

# ---------------------------------------------------------------------------
# Tickers S&P 500
# NOTE : BatchGetSymbols est un vieux package — envisager une solution
#        plus fiable (voir ROADMAP.md).
# ---------------------------------------------------------------------------
tickers <- stringr::str_replace_all(
    BatchGetSymbols::GetSP500Stocks()$Tickers,
    "\\.", "-"
)

# ---------------------------------------------------------------------------
# Connexion PostgreSQL (tunnel SSH en local, localhost sur le VPS)
# ---------------------------------------------------------------------------
con <- dbConnect(
    drv      = RPostgres::Postgres(),
    dbname   = config_global$protegR2$db$dbname,
    host     = config_global$protegR2$db$host,
    port     = config_global$protegR2$db$port,
    user     = config_global$protegR2$db$user,
    password = config_global$protegR2$db$password
)
on.exit(dbDisconnect(con), add = TRUE)

# ---------------------------------------------------------------------------
# Log : initialisation
# ---------------------------------------------------------------------------
# Les fonctions fmp_get()/log_append()/log_flush()/init_log() sont dans R/,
# chargées par devtools::load_all() plus haut.
init_log()
log_env$started_at <- Sys.time()

today <- Sys.Date()
message("=== Début du cron : ", today, " ===")

# ---------------------------------------------------------------------------
# Exécution des étapes (on ajoute chaque fichier au fil de la révision)
# ---------------------------------------------------------------------------
run_reussi <- tryCatch({
  source("inst/script2/01_profiles.R")
  source("inst/script2/02_splits.R")
  source("inst/script2/03_earning_cal.R")
  source("inst/script2/04_statements.R")
  source("inst/script2/05_pricediv.R")
  source("inst/script2/06_tidy_stmts.R")
  source("inst/script2/07_valcagr.R")
  source("inst/script2/08_divbuild.R")
  source("inst/script2/09_quality.R")
  TRUE
}, error = function(e) {
  log_append(etape = "global", statut = "ERROR", message = conditionMessage(e))
  FALSE
})

# ---------------------------------------------------------------------------
# Fin : résumé du log (détail sur S3 + résumé en DB cron_log)
# ---------------------------------------------------------------------------
log_flush(con)

message("=== Fin du cron : ", today, " ===")

