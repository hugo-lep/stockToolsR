# perf_market.R — Performance du marché (vue agrégée globale)
#
# Fonctions :
#   perf_companies(con, horizons) — matrice de performance par compagnie
#   perf_market(con, horizons, fun) — performance globale du marché (moyenne
#     ou médiane des compagnies, par horizon)
#
# Sources : table `stockprice` (prix quotidiens) + `cies_profile_build`
# (sector/industry). Le filtre commun consiste à ne garder que les compagnies
# dont la dernière date de prix correspond à la date de marché commune
# (max(date) de stockprice) : on exclut ainsi les titres au prix périmé et on
# compare toutes les compagnies sur une même base.
#
# La performance d'une compagnie sur un horizon k est calculée sur un nombre
# fixe de lignes de prix (jours de trading), pas sur des dates calendaires :
#   perf = (close_t - close_(t-k)) / close_(t-k)
# avec close_t le dernier prix de la série (le plus récent).

# Colonnes créées et référencées dans des expressions data-masking
# (summarise/mutate) : déclaration pour R CMD check.
utils::globalVariables(c("m", "derniere", "passe", "perf"))

#' Performance par compagnie sur plusieurs horizons
#'
#' @description
#' Charge la table `stockprice`, ne garde que les compagnies dont la dernière
#' date de prix est égale à la date de marché commune (max(date) de
#' `stockprice`), puis calcule la performance en pourcentage sur chaque horizon.
#'
#' @param con Connexion DBI PostgreSQL.
#' @param horizons Vecteur numérique de nombre de lignes (jours de trading) :
#'   ex. `c(1, 5, 21, 63, 252)`.
#'
#' @return Un tibble avec une ligne par compagnie et une colonne par horizon
#'   (nommée `perf_<k>`), plus les colonnes `symbol`, `sector`, `industry`.
#'
#' @importFrom dplyr tbl filter group_by summarise collect arrange desc
#'   select mutate left_join last n row_number tibble pull
#' @importFrom dbplyr in_schema
#' @importFrom rlang :=
#' @importFrom purrr reduce
#'
#' @export
perf_companies <- function(con, horizons = c(1, 5, 21, 63, 252)) {

    # ---- Date de marché commune = max(date) sur toute la table ----
    date_marche <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "stockprice")) |>
        dplyr::summarise(m = max(date, na.rm = TRUE)) |>
        dplyr::collect() |>
        dplyr::pull(m) |>
        as.Date()

    # ---- Compagnies à jour : dernière date = date de marché commune ----
    tickers_a_jour <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "stockprice")) |>
        dplyr::group_by(symbol) |>
        dplyr::summarise(last_date = max(date, na.rm = TRUE)) |>
        dplyr::collect() |>
        dplyr::mutate(last_date = as.Date(last_date)) |>
        dplyr::filter(last_date == date_marche) |>
        dplyr::pull(symbol)

    # ---- Prix des compagnies à jour ----
    prix <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "stockprice")) |>
        dplyr::filter(symbol %in% !!tickers_a_jour) |>
        dplyr::select(symbol, date, close) |>
        dplyr::collect() |>
        dplyr::arrange(symbol, date)

    if (nrow(prix) == 0) {
        stop("Aucun prix disponible pour la date de marché commune.")
    }

    # ---- Performance par compagnie pour chaque horizon ----
    perfs <- perf_from_prices(prix, horizons = horizons)

    # ---- Profils secteur / industrie ----
    profils <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "cies_profile_build")) |>
        dplyr::select(symbol, sector, industry) |>
        dplyr::collect()

    dplyr::left_join(perfs, profils, by = "symbol")
}


#' Calculer la performance par compagnie sur plusieurs horizons
#'
#' @description
#' Fonction pure (testable sans connexion) : à partir d'un dataframe de prix
#' `(symbol, date, close)` trié par date croissante, calcule la performance en
#' pourcentage sur chaque horizon en nombre de lignes (jours de trading).
#'
#' La performance d'une compagnie sur un horizon `k` est
#' `(close[dernier] - close[dernier-k]) / close[dernier-k]`. Elle vaut `NA`
#' si la compagnie n'a pas assez de lignes de prix.
#'
#' @param prix Un data.frame avec les colonnes `symbol`, `date`, `close`.
#' @param horizons Vecteur numérique de nombre de lignes.
#'
#' @return Un tibble avec une colonne `symbol` et une colonne `perf_<k>` par
#'   horizon.
#'
#' @importFrom dplyr group_by mutate row_number summarise n last select rename
#'   left_join tibble
#' @importFrom rlang :=
#' @importFrom purrr reduce
#'
#' @noRd
perf_from_prices <- function(prix, horizons = c(1, 5, 21, 63, 252)) {
    perf_par_horizon <- function(k) {
        prix |>
            dplyr::group_by(symbol) |>
            dplyr::mutate(idx = dplyr::row_number()) |>
            dplyr::summarise(
                n = dplyr::n(),
                derniere = dplyr::last(close),
                # idx du prix k lignes en arrière = n - k ; invalide si <= 0
                passe = close[if (n > k) n - k else NA_integer_],
                .groups = "drop"
            ) |>
            dplyr::mutate(perf = ifelse(n > k, (derniere - passe) / passe, NA_real_)) |>
            dplyr::select(symbol, perf) |>
            dplyr::rename(!!rlang::sym(paste0("perf_", k)) := perf)
    }

    purrr::reduce(horizons, \(acc, k) {
        dplyr::left_join(acc, perf_par_horizon(k), by = "symbol")
    }, .init = dplyr::tibble(symbol = unique(prix$symbol)))
}


#' Extraire les horizons depuis les colonnes perf_* d'un tibble
#'
#' @param df Tibble contenant des colonnes `perf_<k>`.
#' @return Vecteur numérique des horizons `k`.
#' @noRd
extract_horizons <- function(df) {
    cols <- names(df)
    noms <- cols[startsWith(cols, "perf_")]
    as.numeric(sub("^perf_", "", noms))
}


#' Performance globale du marché
#'
#' @description
#' Agrège la performance de toutes les compagnies (même poids) en une valeur
#' unique par horizon, selon `fun` (moyenne ou médiane). C'est l'indicateur
#' synthétique du marché : « +0.8 % aujourd'hui, +2.1 % sur 1 mois ».
#'
#' @param con Connexion DBI PostgreSQL.
#' @param horizons Vecteur numérique de nombre de lignes (jours de trading).
#' @param fun Fonction d'agrégation, une de `mean` ou `median`.
#' @param df Optionnel. Résultat de `perf_companies(con, horizons)`. S'il est
#'   fourni, `con` est ignoré et on agrège directement ce dataframe (évite de
#'   recharger les prix à chaque agrégation, ex. quand on bascule moy/médiane).
#'
#' @return Un tibble avec une ligne et une colonne par horizon, nommée
#'   `perf_<k>`.
#'
#' @importFrom dplyr summarise across all_of
#'
#' @export
perf_market <- function(con, horizons = c(1, 5, 21, 63, 252),
                        fun = mean, df = NULL) {
    fun <- match.fun(fun)

    if (is.null(df)) {
        df <- perf_companies(con, horizons = horizons)
    } else {
        # Horizons dérivés des colonnes perf_* du df fourni
        horizons <- extract_horizons(df)
    }

    df |>
        dplyr::summarise(
            dplyr::across(
                .cols = dplyr::all_of(paste0("perf_", horizons)),
                .fns  = \(x) fun(x, na.rm = TRUE)
            )
        )
}