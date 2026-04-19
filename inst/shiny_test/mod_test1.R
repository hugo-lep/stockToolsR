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

# mod_finance_ui() retourne un tagList de nav_panel.
# do.call() les passe comme arguments séparés à page_navbar()
# (page_navbar n'accepte pas un tagList comme argument unique).
ui <- do.call(
  bslib::page_navbar,
  c(
    list(
      title = "Test \u2014 module finance",
      theme = bslib::bs_theme(bootswatch = "flatly",
                              base_font  = bslib::font_google("Inter"))
    ),
    mod_finance_ui("finance")
  )
)

server <- function(input, output, session) {
  mod_finance_server("finance", con = con)
}

#shiny::onStop(function() DBI::dbDisconnect(con))

shiny::shinyApp(ui, server)
