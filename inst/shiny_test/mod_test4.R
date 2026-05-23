# =============================================================================
# mod_test4.R — Test du module mod_finance4
#
# Prérequis : tunnel SSH actif vers le VPS PostgreSQL
# Lancer depuis RStudio : shiny::runApp("inst/shiny_test/mod_test4.R")
# =============================================================================

library(shiny)
library(bslib)
library(bsicons)
library(dplyr)
library(ggplot2)
library(scales)
library(DBI)
library(RPostgres)
library(lubridate)
library(s3db)
devtools::load_all()

# ── Connexion PostgreSQL ──────────────────────────────────────────────────────
s3_connection_HL(config_path = "../app/data")
config_global <- s3readRDS_HL(object = "config_files/config_global.rds")

con <- dbConnect(
  RPostgres::Postgres(),
  dbname   = "stocktools",
  host     = "localhost",
  port     = 5432,
  user     = config_global$DB_credential$user,
  password = config_global$DB_credential$password
)
dbListTables(con)

# ── Application test ──────────────────────────────────────────────────────────
ui <- bslib::page_fillable(
  theme = bslib::bs_theme(bootswatch = "flatly",
                          base_font  = bslib::font_google("Inter")),
  bslib::navset_bar(
    id = "finance4-main_nav",
    mod_finance4_ui1("finance4"),
    mod_finance4_ui2("finance4")
  )
)

server <- function(input, output, session) {
  mod_finance4_server("finance4", con = con)
}

#shiny::onStop(function() DBI::dbDisconnect(con))

shiny::shinyApp(ui, server)
