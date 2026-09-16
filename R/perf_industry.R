# perf_industry.R — Performance par industrie
#
# Fonctions :
#   perf_industry(con, horizons, fun, df, sector) — performance agrégée par
#     industrie, éventuellement restreinte à un secteur.
#
# Réutilise perf_companies() (R/perf_market.R) comme base commune : même filtre
# de date de marché commune, mêmes calculs de performance par horizon. Ici on
# agrège les compagnies de chaque industrie selon `fun` (moyenne ou médiane,
# même poids pour toutes les compagnies).

#' Performance agrégée par industrie
#'
#' @description
#' Agrège la performance des compagnies de chaque industrie (même poids) en une
#' valeur par horizon, selon `fun` (moyenne ou médiane). Le paramètre `sector`
#' permet de restreindre aux industries d'un secteur donné (ex. pour l'expansion
#' d'un secteur dans le module marché).
#'
#' @param con Connexion DBI PostgreSQL.
#' @param horizons Vecteur numérique de nombre de lignes (jours de trading).
#' @param fun Fonction d'agrégation, une de `mean` ou `median`.
#' @param df Optionnel. Résultat de `perf_companies(con, horizons)`. S'il est
#'   fourni, `con` est ignoré et on agrège directement ce dataframe.
#' @param sector Optionnel. Si non NULL, ne garde que les compagnies de ce
#'   secteur.
#'
#' @return Un tibble avec une ligne par industrie et une colonne `n_companies`
#'   (nombre de compagnies) plus une colonne par horizon, nommée `perf_<k>`.
#'
#' @importFrom dplyr summarise across all_of group_by n filter
#' @importFrom rlang .data
#'
#' @export
perf_industry <- function(con, horizons = c(1, 5, 21, 63, 252),
                          fun = mean, df = NULL, sector = NULL) {
    fun <- match.fun(fun)

    if (is.null(df)) {
        df <- perf_companies(con, horizons = horizons)
    } else {
        # Horizons dérivés des colonnes perf_* du df fourni
        horizons <- extract_horizons(df)
    }

    if (!is.null(sector)) {
        df <- dplyr::filter(df, .data$sector == !!sector)
    }

    df |>
        dplyr::group_by(industry) |>
        dplyr::summarise(
            n_companies = dplyr::n(),
            dplyr::across(
                .cols = dplyr::all_of(paste0("perf_", horizons)),
                .fns  = \(x) fun(x, na.rm = TRUE)
            ),
            .groups = "drop"
        )
}