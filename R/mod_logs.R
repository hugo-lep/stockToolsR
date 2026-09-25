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
#' @importFrom shiny NS selectInput tableOutput actionButton tagList
#' @importFrom bsicons bs_icon
#' @importFrom bslib card card_body
#'
#' @export
mod_logs_ui <- function(id) {
    ns <- shiny::NS(id)
    bslib::card(
        bslib::card_header("Logs du cron"),
        bslib::card_body(
            shiny::tagList(
                shiny::div(
                    class = "d-flex align-items-center gap-2",
                    shiny::div(
                        style = "flex:1;",
                        shiny::selectInput(ns("choix_date"), "Date du log",
                                           choices = NULL)
                    ),
                    shiny::actionButton(
                        ns("reset_dates"),
                        label = shiny::tagList(
                            bsicons::bs_icon("arrow-clockwise"),
                            " Recharger"
                        ),
                        title = "Recharger les dates de logs disponibles"
                    )
                ),
                shiny::tableOutput(ns("summary")),
                shiny::tableOutput(ns("detail"))
            )
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
#'   invalidateLater observeEvent
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
        #
        # tryCatch : une erreur S3 transitoire (ex. connexion froide au premier
        # appel, timeout réseau) ne doit PAS casser l'observe définitivement.
        # Sans ce garde, l'observe plante une seule fois et le sélecteur reste
        # vide pour toute la session — on bascule plutôt sur invalidateLater()
        # pour re-tenter.
        shiny::observe({
            dates <- tryCatch(
                log_list_dates(),
                error = function(e) {
                    warning("mod_logs : log_list_dates() a échoué — re-tentative : ",
                            conditionMessage(e))
                    NULL
                }
            )
            if (length(dates) > 0) {
                shiny::updateSelectInput(session, "choix_date",
                                         choices = dates)
            } else {
                shiny::invalidateLater(1000, session)
            }
        })

        # Bouton "Recharger" : force le rechargement des dates S3 et met à jour
        # le sélecteur. Utile si la connexion S3 n'était pas prête au démarrage
        # ou a changé en cours de session.
        shiny::observeEvent(input$reset_dates, {
            dates <- tryCatch(
                log_list_dates(),
                error = function(e) {
                    warning("mod_logs : log_list_dates() a échoué (reset) : ",
                            conditionMessage(e))
                    NULL
                }
            )
            shiny::updateSelectInput(session, "choix_date",
                                     choices = if (length(dates) > 0) dates
                                               else character(0))
        })

        # Détail des logs de la date sélectionnée
        detail <- shiny::reactive({
            shiny::req(input$choix_date)
            tryCatch(
                log_get_detail(input$choix_date),
                error = function(e) {
                    warning("mod_logs : log_get_detail() a échoué pour ",
                            input$choix_date, " : ", conditionMessage(e))
                    NULL
                }
            )
        })

        output$detail <- shiny::renderTable({
            detail()
        })

        invisible(NULL)
    })
}