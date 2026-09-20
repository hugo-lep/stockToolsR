# mod_logs.R — Module Shiny : consultation des logs du cron
#
# Module autonome : affiche le résumé des derniers runs (table cron_log),
# un sélecteur de jour (dates disponibles sur S3) et le détail des logs
# du jour sélectionné.
#
# Fonctions exportées :
#   mod_logs_ui(id)          — UI du module
#   mod_logs_server(id, con) — logique serveur
#
# Dépend des fonctions de lecture : log_get_summary(), log_list_dates(),
# log_get_detail() (R/1-log_fcts.R).

#' UI du module de consultation des logs
#'
#' @param id Identifiant du module (Shiny).
#'
#' @return Une UI Shiny (card bslib).
#'
#' @importFrom shiny NS selectInput tableOutput
#' @importFrom bslib card card_body
#'
#' @export
mod_logs_ui <- function(id) {
    ns <- shiny::NS(id)
    bslib::card(
        bslib::card_header("Logs du cron"),
        bslib::card_body(
            shiny::selectInput(ns("choix_date"), "Date du log", choices = NULL),
            shiny::tableOutput(ns("summary")),
            shiny::tableOutput(ns("detail"))
        )
    )
}

#' Server du module de consultation des logs
#'
#' @param id  Identifiant du module (Shiny).
#' @param con Connexion DBI PostgreSQL.
#'
#' @return Invisiblement NULL.
#'
#' @importFrom shiny moduleServer renderTable req reactive updateSelectInput
#'   invalidateLater
#'
#' @export
mod_logs_server <- function(id, con) {
    shiny::moduleServer(id, function(input, output, session) {

        # Résumé des derniers runs (table cron_log)
        output$summary <- shiny::renderTable({
            log_get_summary(con, n = 10) |>
                dplyr::mutate(
                    run_date    = format(.data$run_date, "%Y-%m-%d"),
                    started_at  = format(.data$started_at, "%Y-%m-%d %H:%M:%S"),
                    finished_at = format(.data$finished_at, "%Y-%m-%d %H:%M:%S")
                )
        })

        # Mise à jour du sélecteur avec les dates disponibles sur S3.
        # Tant que S3 n'est pas prêt (course d'initialisation au démarrage de
        # l'app), on re-tente périodiquement ; dès que des dates existent, on
        # remplit le sélecteur et on arrête de re-tenter.
        shiny::observe({
            dates <- log_list_dates()
            if (length(dates) > 0) {
                shiny::updateSelectInput(session, "choix_date",
                                         choices = dates)
            } else {
                shiny::invalidateLater(1000, session)
            }
        })

        # Détail des logs de la date sélectionnée
        detail <- shiny::reactive({
            shiny::req(input$choix_date)
            log_get_detail(input$choix_date)
        })

        output$detail <- shiny::renderTable({
            detail()
        })

        invisible(NULL)
    })
}