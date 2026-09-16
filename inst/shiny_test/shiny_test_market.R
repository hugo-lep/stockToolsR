# shiny_test_market.R — Test du module mod_market (vue marché)
#
# Deux modes :
#   1. Connexion réelle (par défaut) : requiert un tunnel SSH actif vers le
#      PostgreSQL du VPS et l'accès S3 (protegR2).
#      ssh -L 5432:127.0.0.1:5432 hugo@158.69.221.155
#   2. Données factices : UTILISER_FACTICE <- TRUE pour tester le module sans
#      base ni S3 (injection d'un `companies_df` pré-calculé).
#
# Lancer depuis RStudio : shiny::runApp("inst/shiny_test/shiny_test_market.R")

library(shiny)
library(bslib)
library(dplyr)
library(DBI)
library(RPostgres)
library(s3db)
devtools::load_all()
devtools::document()

# ---------------------------------------------------------------------------
# Mode factice (pas de DB) : TRUE pour tester sans tunnel SSH / S3
# ---------------------------------------------------------------------------
UTILISER_FACTICE <- FALSE

if (isTRUE(UTILISER_FACTICE)) {

    # Jeu de données factice : 3 compagnies, 6 jours de prix, 2 secteurs
    dates <- as.Date("2026-01-01") + 0:5
    prix <- data.frame(
        symbol = c(rep("AAPL", 6), rep("MSFT", 6), rep("T", 6)),
        date   = rep(dates, 3),
        close  = c(
            100, 101, 102, 103, 104, 105,   # AAPL : +5 % en 5 jours
            50,  50,  50,  50,  50,  50,    # MSFT : stable
            200, 210, 190, 205, 220, 215    # T    : volatile
        )
    )

    companies_df <- perf_from_prices(prix, horizons = c(1, 5, 21, 63, 252))
    companies_df$sector   <- c("Technology", "Technology", "Communication Services")
    companies_df$industry <- c("Hardware", "Software", "Telecom")

} else {

    # ---------------------------------------------------------------------------
    # Connexion PostgreSQL (tunnel SSH en local, localhost sur le VPS)
    # ---------------------------------------------------------------------------
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
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    companies_df <- NULL
}

# ---------------------------------------------------------------------------
# Application test
# ---------------------------------------------------------------------------
ui <- bslib::page_fillable(
    theme = bslib::bs_theme(
        bootswatch = "flatly",
        base_font  = bslib::font_google("Inter")
    ),
    mod_market_ui("market")
)

server <- function(input, output, session) {
    mod_market_server(
        "market",
        con = if (isTRUE(UTILISER_FACTICE)) NULL else con,
        companies_df = companies_df
    )
}

shiny::shinyApp(ui, server)

