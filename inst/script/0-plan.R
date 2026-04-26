# =============================================================================
# 0-plan.R — Point d'entrée du cron quotidien
# Exécution : Rscript inst/script/0-plan.R
# =============================================================================
# ssh -L 5432:127.0.0.1:5432 hugo@158.69.221.155

library(here)
library(DBI)
library(RPostgres)
#library(tidyquant)
library(dplyr)
library(tidyr)
library(s3db)
library(lubridate)
library(devtools)
library(glue)
library(BatchGetSymbols)
library(stringr)

devtools::load_all()

today       <- Sys.Date()
#tickers <- fmp_company_screener(key_fmp_api, "NASDAQ") %>% pull(symbol) %>%  head(1500)
#tickers   <- fmp_company_screener(key_fmp_api, "NYSE")
#tickers   <- fmp_company_screener(key_fmp_api, "AMEX")
#tickers <- tq_index("SP500")$symbol |> setdiff(c("-","2602335D"))
tickers <- str_replace_all(GetSP500Stocks()$Tickers, "\\.", "-")

s3_connection_HL()
config_global <- s3readRDS_HL(object = "config_files/config_global.rds")
key_fmp_api <- config_global$key_fmp_api
save_path  <- "data/cies_order.rds"

# connecter tunnel SSH: ssh -L 5433:127.0.0.1:5432 hugo@158.69.221.155
con <- dbConnect(
  RPostgres::Postgres(),
  dbname   = "stocktools",
  host     = "localhost",
  port     = 5432,
  user     = config_global$DB_credential$user,
  password = config_global$DB_credential$password
)
on.exit(dbDisconnect(con), add = TRUE)

message("=== Début du cron : ", today, " ===")

start_time <- Sys.time()
dbListTables(con)
source("inst/script/1-profiles.R")
source("inst/script/2-splits_detection.R")
source("inst/script/3-splits_processing.R")
s3db::s3readRDS_HL(save_path) %>% as_tibble()
source("inst/script/4-earnings_calendar.R")
source("inst/script/5-statements_import.R")
source("inst/script/6-statements_check.R")
s3db::s3readRDS_HL(save_path) %>% as_tibble()
source("inst/script/7-stockprice.R")
source("inst/script/8-dividends.R")
source("inst/script/9-tidy_stmts.R")
source("inst/script/10-ratios.R")

cat("temps de traitement",Sys.time() - start_time)
message("=== Fin du cron : ", today, " ===")


dbListTables(con)
#  table de travail:
cies_profile_build <- dbReadTable(con,"cies_profile_build")
#stockprice <- dbReadTable(con,"stockprice")
#dividendes <- dbReadTable(con,"dividendes")
financial_stmts_build <- dbReadTable(con,"financial_stmts_build")

names(financial_stmts_build)
financial_stmts_build2 <- financial_stmts_build %>%
  group_by(symbol) %>%
  arrange(desc(date)) %>%
  slice(1)
cagr_price_build <- dbReadTable(con,"cagr_price_build")
cagr_stmts_build <- dbReadTable(con,"cagr_stmts_build")
valuation_build <- dbReadTable(con,"valuation_build")
valuation_build2 <- valuation_build %>%
  group_by(symbol) %>%
  arrange(desc(date)) %>%
  slice(1)

cies_profile_build$sector %>% unique()
test <- valuation_build2 %>%
  left_join(cies_profile_build, by = join_by(symbol)) %>%
  filter(sector == "Consumer Defensive") %>%
  mutate(profit_s = round(caution_p_to_s - close,2),
         profit_s_percent = profit_s / close,
         close_ratio_s = round((close - buy_p_to_s) / (sell_p_to_s - buy_p_to_s),2)) %>%
  mutate(profit_e = round(caution_pe - close,2),
         profit_e_percent = profit_e / close,
         close_ratio_e = round((close - buy_pe) / (sell_pe - buy_pe),2)) %>%
  filter(close_ratio_s <= 0.1)

names(dbReadTable(con,"qts_income_stmts_orig"))
names(dbReadTable(con,"qts_balance_stmts_orig"))
names(dbReadTable(con,"qts_income_stmts_orig"))

test <- tbl(con, "valuation_build") |>
  group_by(symbol) |>
  slice_max(date, n = 1) |>
  collect() %>%
  glimpse()

test2 <- test %>%
  mutate(ratio = (close - buy_p_to_s)/ (sell_p_to_s - buy_p_to_s))



#test2 <- dbReadTable(con,"qts_income_stmts_orig") %>%
#  filter(symbol == "PLTR")


