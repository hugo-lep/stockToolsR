# perf_sector.R — Performance par secteur
#
# Fonctions :
#   perf_sector(con, horizons, fun) — performance agrégée par secteur
#
# Réutilise perf_companies() (R/perf_market.R) comme base commune : même filtre
# de date de marché commune, mêmes calculs de performance par horizon. Ici on
# agrège simplement les compagnies de chaque secteur selon `fun` (moyenne ou
# médiane, même poids pour toutes les compagnies).

#' Performance agrégée par secteur
#'
#' @description
#' Agrège la performance des compagnies de chaque secteur (même poids) en une
#' valeur par horizon, selon `fun` (moyenne ou médiane). Une compagnie sans
#' secteur déclaré est regroupée dans un secteur `NA`.
#'
#' @param con Connexion DBI PostgreSQL.
#' @param horizons Vecteur numérique de nombre de lignes (jours de trading).
#' @param fun Fonction d'agrégation, une de `mean` ou `median`.
#' @param df Optionnel. Résultat de `perf_companies(con, horizons)`. S'il est
#'   fourni, `con` est ignoré et on agrège directement ce dataframe (évite de
#'   recharger les prix à chaque agrégation, ex. quand on bascule moy/médiane).
#'
#' @return Un tibble avec une ligne par secteur et une colonne `n_companies`
#'   (nombre de compagnies) plus une colonne par horizon, nommée `perf_<k>`.
#'
#' @importFrom dplyr summarise across all_of group_by n
#'
#' @export
perf_sector <- function(con, horizons = c(1, 5, 21, 63, 252),
                        fun = mean, df = NULL) {
    fun <- match.fun(fun)

    if (is.null(df)) {
        df <- perf_companies(con, horizons = horizons)
    } else {
        # Horizons dérivés des colonnes perf_* du df fourni
        horizons <- extract_horizons(df)
    }

    df |>
        dplyr::group_by(sector) |>
        dplyr::summarise(
            n_companies = dplyr::n(),
            dplyr::across(
                .cols = dplyr::all_of(paste0("perf_", horizons)),
                .fns  = \(x) fun(x, na.rm = TRUE)
            ),
            .groups = "drop"
        )
}