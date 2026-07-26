# shiny_test6.R — Test du module mod_finance6
#
# Prérequis : tunnel SSH actif vers le VPS PostgreSQL
# Lancer depuis RStudio : shiny::runApp("inst/shiny_test/shiny_test6.R")

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

# Connexion PostgreSQL
s3_connection_HL(config_path = "../app/data")
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
    mod_finance6_ui("finance6")
)

server <- function(input, output, session) {
    mod_finance6_server("finance6", con = con)
}

#shiny::onStop(function() DBI::dbDisconnect(con))

shiny::shinyApp(ui, server)
