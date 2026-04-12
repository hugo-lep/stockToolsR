# =============================================================================
# 0-plan.R — Point d'entrée du cron quotidien
# Exécution : Rscript inst/script/0-plan.R
# =============================================================================

library(here)
library(DBI)
library(RPostgres)
library(tidyquant)
library(dplyr)
library(s3db)

devtools::load_all()

today       <- Sys.Date()
tickers <- tq_index("SP500")$symbol |> setdiff("-") |> head(12)

s3_connection_HL()
config_global <- s3readRDS_HL(object = "config_files/config_global.rds")
key_fmp_api <- config_global$key_fmp_api

# connecter tunnel SSH: ssh -L 5433:127.0.0.1:5432 hugo@158.69.221.155
con <- dbConnect(
  RPostgres::Postgres(),
  dbname   = "stocktools",
  host     = "localhost",
  port     = 5433,
  user     = config_global$DB_credential$user,
  password = config_global$DB_credential$password
)
on.exit(dbDisconnect(con), add = TRUE)

message("=== Début du cron : ", today, " ===")

source("inst/script/1-profiles.R")
source("inst/script/2-splits_detection.R")
source("inst/script/3-splits_processing.R")
source("inst/script/4-earnings_calendar.R")
source("inst/script/5-statements_import.R")
source("inst/script/6-statements_check.R")
source("inst/script/7-stockprice.R")
source("inst/script/8-dividends.R")
source("inst/script/9-tidy_stmts.R")

message("=== Fin du cron : ", today, " ===")

#dbListTables(con)
#test <- dbReadTable(con,"fy_balance_stmts_orig")
#test2 <- dbReadTable(con,"qts_income_stmts_orig") %>%
#  filter(symbol == "PLTR")
