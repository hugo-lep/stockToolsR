# =============================================================================
# mod_test1.R — Test du module mod_finance
#
# Prérequis : tunnel SSH actif vers le VPS PostgreSQL
# Lancer depuis RStudio : shiny::runApp("inst/shiny_test/mod_test1.R")
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
devtools::load_all()   # charge mod_finance_ui() et mod_finance_server()

# ── Connexion PostgreSQL ──────────────────────────────────────────────────────
s3_connection_HL()
config_global <- s3readRDS_HL(object = "config_files/config_global.rds")

con <- dbConnect(
  RPostgres::Postgres(),
  dbname   = "stocktools",
  host     = "localhost",
  port     = 5433,
  user     = config_global$DB_credential$user,
  password = config_global$DB_credential$password
)
dbListTables(con)
# ── Application test ──────────────────────────────────────────────────────────

# mod_finance_ui() retourne un navset_bar() autonome — on l'imbrique
# directement dans page_fluid() sans do.call.
ui <- bslib::page_fluid(
  theme = bslib::bs_theme(bootswatch = "flatly",
                          base_font  = bslib::font_google("Inter")),
  mod_finance_ui("finance")
)

server <- function(input, output, session) {
  mod_finance_server("finance", con = con)
}

#shiny::onStop(function() DBI::dbDisconnect(con))

shiny::shinyApp(ui, server)
