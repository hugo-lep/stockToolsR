# shiny_test_logs.R — Test du module mod_logs
#
# Prérequis : tunnel SSH actif vers le VPS PostgreSQL
# Lancer depuis RStudio : shiny::runApp("inst/shiny_test/shiny_test_logs.R")

library(shiny)
library(bslib)
library(dplyr)
library(DBI)
library(RPostgres)
library(s3db)
devtools::load_all()

# Connexion PostgreSQL
s3_connection_HL()
config_global <- s3readRDS_HL(object = "config_files/config_global.rds")

con <- dbConnect(
    drv      = RPostgres::Postgres(),
    dbname   = config_global$protegR2$db$dbname,
    host     = config_global$protegR2$db$host,
    port     = config_global$protegR2$db$port,
    user     = config_global$protegR2$db$user,
    password = config_global$protegR2$db$password
)

# Application test
ui <- bslib::page_fillable(
    theme = bslib::bs_theme(
        bootswatch = "flatly",
        base_font  = bslib::font_google("Inter")
    ),
    mod_logs_ui("logs")
)

server <- function(input, output, session) {
    mod_logs_server("logs", con = con)
}

#shiny::onStop(function() DBI::dbDisconnect(con))

shiny::shinyApp(ui, server)

