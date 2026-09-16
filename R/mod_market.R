# mod_market.R — Module Shiny : vue marché (compagnies, secteurs, industries)
#
# Module autonome : un seul onglet avec
#   - un bandeau « marché » (valeur globale par horizon, moy/méd des compagnies)
#   - un toggle moyenne/médiane qui recalcule toutes les performances
#   - un tableau des secteurs, triable par colonne, avec expansion cliquable
#     vers les compagnies qui composent chaque secteur.
#
# La partie « industries » (perf_industry) est prévue pour une phase 2 : elle
# s'imbriquera dans le tableau des secteurs (une couche d'expansion de plus).
#
# Fonctions exportées :
#   mod_market_ui(id)          — UI du module
#   mod_market_server(id, con) — logique serveur
#
# Dépend des fonctions data :
#   perf_companies(), perf_market(), perf_sector() (R/perf_market.R, R/perf_sector.R)

#' UI du module de vue marché
#'
#' @param id Identifiant du module (Shiny).
#'
#' @return Une UI Shiny (card bslib).
#'
#' @importFrom shiny NS uiOutput
#' @importFrom bslib card card_header card_body layout_columns input_switch
#'
#' @export
mod_market_ui <- function(id) {
    ns <- shiny::NS(id)
    bslib::card(
        bslib::card_header("Vue marché"),
        bslib::card_body(
            # Bandeau marché (rendu dynamique, une value_box par horizon)
            shiny::uiOutput(ns("market_stats")),
            # Toggle moyenne / médiane
            bslib::input_switch(
                id    = ns("metric"),
                label = "Médiane"
            ),
            # Tableau des secteurs
            reactable::reactableOutput(ns("sector_table"))
        )
    )
}

#' Server du module de vue marché
#'
#' @param id        Identifiant du module (Shiny).
#' @param con       Connexion DBI PostgreSQL.
#' @param horizons  Vecteur numérique de nombre de lignes (jours de trading).
#' @param companies_df Optionnel. Résultat de `perf_companies(con, horizons)`.
#'   S'il est fourni, `con` est ignoré et on utilise directement ce dataframe
#'   (utile pour tester le module sans base, ou pour éviter un rechargement).
#'
#' @return Invisiblement NULL.
#'
#' @importFrom shiny moduleServer reactive renderUI
#' @importFrom bslib value_box layout_columns
#' @importFrom reactable reactable colDef colFormat renderReactable
#' @importFrom rlang .data exec
#' @importFrom purrr map
#' @importFrom dplyr filter select all_of
#'
#' @export
mod_market_server <- function(id, con, horizons = c(1, 5, 21, 63, 252),
                              companies_df = NULL) {
    shiny::moduleServer(id, function(input, output, session) {

        # Fonction d'agrégation selon le toggle (FALSE -> moyenne, TRUE -> médiane)
        metric <- shiny::reactive({
            if (isTRUE(input$metric)) stats::median else base::mean
        })

        # Matrice de performance par compagnie (chargée une seule fois)
        companies <- shiny::reactive({
            if (is.null(companies_df)) {
                perf_companies(con, horizons = horizons)
            } else {
                companies_df
            }
        })

        # Bandeau marché global
        market <- shiny::reactive({
            perf_market(df = companies(), fun = metric())
        })

        # Table des secteurs
        sectors <- shiny::reactive({
            perf_sector(df = companies(), fun = metric())
        })

        # ---- Bandeau marché : une value_box par horizon ----
        output$market_stats <- shiny::renderUI({
            mkt <- market()
            boxes <- purrr::map(horizons, \(k) {
                val <- mkt[[paste0("perf_", k)]]
                thm <- if (is.na(val) || val >= 0) "success" else "danger"
                bslib::value_box(
                    title = horizon_label(k),
                    value = pct_format(val),
                    theme = thm
                )
            })
            rlang::exec(bslib::layout_columns, !!!boxes)
        })

        # ---- Tableau des secteurs (tri cliquable + expand industries) ----
        output$sector_table <- reactable::renderReactable({
            # Colonnes de performance par horizon
            perf_cols <- purrr::map(horizons, \(k) {
                reactable::colDef(
                    header = horizon_label(k),
                    format = reactable::colFormat(percent = TRUE, digits = 2),
                    align  = "right"
                )
            })
            names(perf_cols) <- paste0("perf_", horizons)

            # Colonne d'expansion -> mini-table des industries du secteur.
            # La fonction `details` est attachée à la colonne `sector`.
            base_cols <- list(
                sector = reactable::colDef(
                    name    = "Secteur",
                    sticky  = "left",
                    details = function(index) {
                        sec <- sectors()$sector[index]
                        ind <- perf_industry(
                            df = companies(), sector = sec,
                            fun = metric()
                        )
                        build_industry_table(
                            ind, horizons,
                            comp = companies(), secteur = sec
                        )
                    }
                )
            )

            reactable::reactable(
                data    = sectors(),
                columns = c(base_cols, perf_cols),
                sortable = TRUE,
                compact  = TRUE,
                striped  = TRUE,
                pagination = FALSE
            )
        })

        invisible(NULL)
    })
}

#' Formater une valeur de performance (fraction) en pourcentage lisible
#'
#' @param x Valeur numérique (fraction, ex. 0.008 -> "+0.8 %").
#' @noRd
pct_format <- function(x) {
    if (is.na(x)) return("NA")
    paste0(if (x >= 0) "+" else "",
           formatC(x * 100, digits = 2, format = "f"), " %")
}

#' Construire le libellé d'un horizon
#'
#' @param k Nombre de lignes (jours de trading).
#' @noRd
horizon_label <- function(k) {
    switch(as.character(k),
        "1"   = "1 jour",
        "5"   = "5 jours",
        "21"  = "1 mois",
        "63"  = "3 mois",
        "252" = "1 an",
        paste0(k, " lignes")
    )
}

#' Construire la mini-table reactable des industries d'un secteur,
#' avec expansion vers les compagnies de chaque industrie.
#'
#' @param ind Tibble des industries (industry, n_companies, perf_*).
#' @param horizons Vecteur numérique des horizons.
#' @param comp Tibble des compagnies (symbol, sector, industry, perf_*).
#' @param secteur Secteur courant (chaîne), pour filtrer les compagnies.
#' @noRd
build_industry_table <- function(ind, horizons, comp = NULL, secteur = NULL) {
    ccols <- purrr::map(horizons, \(k) {
        reactable::colDef(
            header = horizon_label(k),
            format = reactable::colFormat(percent = TRUE, digits = 2),
            align  = "right"
        )
    })
    names(ccols) <- paste0("perf_", horizons)

    # Colonne d'expansion -> mini-table des compagnies de l'industrie.
    industry_col <- reactable::colDef(
        name = "Industrie",
        details = function(index) {
            ind_name <- ind$industry[index]
            comp_sec <- if (is.null(comp)) NULL else comp |>
                dplyr::filter(.data$sector == secteur,
                              .data$industry == ind_name) |>
                dplyr::select(
                    "symbol",
                    dplyr::all_of(paste0("perf_", horizons))
                )
            build_company_table(comp_sec, horizons)
        }
    )

    reactable::reactable(
        data    = ind,
        columns = c(
            list(
                industry    = industry_col,
                n_companies = reactable::colDef(name = "Nb")
            ),
            ccols
        ),
        sortable    = TRUE,
        compact     = TRUE,
        pagination  = FALSE,
        style = list(
            backgroundColor = "#f7f7f7",
            border          = "1px solid #ddd"
        )
    )
}

#' Construire la mini-table reactable des compagnies d'une industrie
#'
#' @param comp Tibble des compagnies (symbol, perf_*).
#' @param horizons Vecteur numérique des horizons.
#' @noRd
build_company_table <- function(comp, horizons) {
    ccols <- purrr::map(horizons, \(k) {
        reactable::colDef(
            header = horizon_label(k),
            format = reactable::colFormat(percent = TRUE, digits = 2),
            align  = "right"
        )
    })
    names(ccols) <- paste0("perf_", horizons)

    reactable::reactable(
        data    = comp,
        columns = c(
            list(
                symbol = reactable::colDef(name = "Symbole")
            ),
            ccols
        ),
        sortable    = TRUE,
        compact     = TRUE,
        pagination  = FALSE,
        style = list(
            backgroundColor = "#f3f3f3",
            border          = "1px solid #ccc"
        )
    )
}