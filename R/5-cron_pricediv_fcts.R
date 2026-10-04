#' Mettre à jour la table stockprice
#'
#' @description
#' Met à jour les prix boursiers dans la table `stockprice` pour un vecteur
#' de symboles. Effectue deux appels `tq_get()` distincts :
#'
#' - **Symboles déjà présents** : télécharge depuis la date la plus ancienne
#'   des dernières mises à jour, jusqu'à hier.
#' - **Nouveaux symboles** (absents de la table, ex: post-split) : télécharge
#'   les 12 dernières années, jusqu'à hier.
#'
#' Les doublons éventuels sont éliminés par `anti_join()` avant insertion.
#'
#' @param con Connexion DBI
#' @param symbols Vecteur de tickers à mettre à jour
#'
#' @return Invisiblement TRUE.
#'
#' @importFrom tidyquant tq_get
#' @importFrom dplyr tbl filter group_by summarise collect mutate bind_rows
#'   select anti_join pull
#' @importFrom tibble tibble
#' @importFrom lubridate years
#' @importFrom DBI dbWriteTable
#'
#' @export
#'
#' @examples
#' \dontrun{
#' update_stockprice(con, c("AAPL", "MSFT"))
#' }
update_stockprice <- function(con, symbols) {

    to_date <- Sys.Date()

    # dates max déjà en base pour les symboles demandés
    existing_dates <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "stockprice")) |>
        dplyr::filter(symbol %in% !!symbols) |>
        dplyr::group_by(symbol) |>
        dplyr::summarise(last_date = max(date, na.rm = TRUE)) |>
        dplyr::collect() |>
        dplyr::mutate(last_date = as.Date(last_date))

    existing_symbols <- existing_dates$symbol
    missing_symbols  <- setdiff(symbols, existing_symbols)

    # Appel 1 : symboles déjà présents
    if (length(existing_symbols) > 0) {
        from_date <- min(existing_dates$last_date) + 1

        if (from_date <= to_date) {
            message("Mise à jour de ", length(existing_symbols), " ticker(s) depuis le ", from_date, "...")

            df_new <- tidyquant::tq_get(existing_symbols, from = from_date, to = to_date) |>
                dplyr::select(-adjusted) |>
                dplyr::filter(date != to_date)

            df_existing_keys <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "stockprice")) |>
                dplyr::filter(symbol %in% !!existing_symbols, date >= !!from_date) |>
                dplyr::select(symbol, date) |>
                dplyr::collect()

            df_to_add <- dplyr::anti_join(df_new, df_existing_keys, by = c("symbol", "date"))

            if (nrow(df_to_add) > 0) {
                DBI::dbWriteTable(
                    conn   = con,
                    name   = DBI::Id(schema = "stocktools", table = "stockprice"),
                    value  = df_to_add,
                    append = TRUE
                )
                message(nrow(df_to_add), " ligne(s) ajoutée(s) pour les tickers existants.")
            } else {
                message("Rien à ajouter pour les tickers existants.")
            }
        } else {
            message("Tickers existants déjà à jour.")
        }
    }

    # Appel 2 : nouveaux symboles (post-split ou première fois)
    if (length(missing_symbols) > 0) {
        from_date_new <- Sys.Date() - lubridate::years(12)
        message("Import complet pour ", length(missing_symbols), " nouveau(x) ticker(s) : ",
                paste(missing_symbols, collapse = ", "))

        df_new <- tidyquant::tq_get(missing_symbols, from = from_date_new, to = to_date) |>
            dplyr::select(-adjusted) |>
            dplyr::filter(date != to_date)

        if (!is.null(df_new) && nrow(df_new) > 0) {
            DBI::dbWriteTable(
                conn   = con,
                name   = DBI::Id(schema = "stocktools", table = "stockprice"),
                value  = df_new,
                append = TRUE
            )
            message(nrow(df_new), " ligne(s) ajoutée(s) pour les nouveaux tickers.")
        }
    }

    invisible(TRUE)
}
