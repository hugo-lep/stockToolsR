# =============================================================================
# mod_test3.R — Test du module mod_finance3
#
# Prérequis : tunnel SSH actif vers le VPS PostgreSQL
# Lancer depuis RStudio : shiny::runApp("inst/shiny_test/mod_test3.R")
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
ui <- bslib::page_fluid(
  theme = bslib::bs_theme(bootswatch = "flatly",
                          base_font  = bslib::font_google("Inter")),
  bslib::navset_bar(
    mod_finance3_ui1("finance3"),
    mod_finance3_ui2("finance3")
  )
)

server <- function(input, output, session) {
  mod_finance3_server("finance3", con = con)
}

#shiny::onStop(function() DBI::dbDisconnect(con))

shiny::shinyApp(ui, server)
