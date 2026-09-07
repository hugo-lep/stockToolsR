# 9-cron_dividendbuild2_fcts.R — Reconstruire dividendes_build (version révisée)
#
# Version v2 de build_dividendes_build() : même logique métier (via
# .calc_div_symbol() de R/8), mais écriture transactionnelle (TRUNCATE +
# append dans dbWithTransaction) au lieu d'un TRUNCATE non transactionnel.

#' Reconstruire la table `dividendes_build`
#'
#' @description
#' Pour chaque symbol présent dans la table `dividendes`, calcule les métriques
#' de dividendes (TTM, forward, CAGR 1/3/5/10 ans, yield, drapeaux
#' Special/Irregular, ratios FCF) et écrit le résultat dans `dividendes_build`.
#'
#' Le prix de référence (`close_ref`) est lu depuis `valuation_build` et les
#' ratios FCF depuis `financial_stmts_build`. Les dividendes `"Special"` et
#' `"Irregular"` sont exclus du TTM/CAGR mais signalés via les drapeaux.
#'
#' L'écriture est faite en transaction (TRUNCATE + append) : si elle échoue,
#' la table existante est préservée.
#'
#' @param con Connexion DBI active (PostgreSQL).
#'
#' @return Invisiblement le tibble écrit dans `dividendes_build`.
#'
#' @importFrom dplyr group_by group_split bind_rows left_join rename mutate select
#' @importFrom DBI dbReadTable dbGetQuery dbExecute dbWriteTable dbWithTransaction
#'   dbExistsTable
#' @importFrom lubridate years
#' @importFrom purrr map
#' @importFrom tibble tibble
#'
#' @export
build_dividendes_build2 <- function(con) {

    message("  [1/4] Chargement des dividendes...")
    dividendes <- DBI::dbReadTable(
        con,
        DBI::Id(schema = "stocktools", table = "dividendes")
    ) |>
        dplyr::mutate(date = as.Date(date))

    message("  [2/4] Chargement des prix de référence (valuation_build)...")
    close_df <- DBI::dbGetQuery(con, "
    SELECT DISTINCT ON (symbol) symbol, close
    FROM stocktools.valuation_build
    ORDER BY symbol, date DESC
  ")

    message("  [3/4] Chargement FCF et actions (financial_stmts_build)...")
    fcf_df <- DBI::dbGetQuery(con, "
    SELECT DISTINCT ON (symbol)
      symbol, cf_freecashflow, is_weightedaverageshsout
    FROM stocktools.financial_stmts_build
    ORDER BY symbol, date DESC
  ")

    message("  [4/4] Calcul des métriques par symbol...")
    result <- dividendes |>
        dplyr::group_by(symbol) |>
        dplyr::group_split() |>
        purrr::map(.calc_div_symbol) |>
        dplyr::bind_rows() |>
        dplyr::left_join(close_df, by = "symbol") |>
        dplyr::left_join(fcf_df,   by = "symbol") |>
        dplyr::rename(close_ref = close) |>
        dplyr::mutate(
            yield = dplyr::if_else(
                !is.na(div_forward) & !is.na(close_ref) & close_ref > 0,
                div_forward / close_ref,
                NA_real_
            ),
            .div_total = dplyr::if_else(
                !is.na(div_ttm) & div_ttm > 0 &
                !is.na(is_weightedaverageshsout) & is_weightedaverageshsout > 0,
                div_ttm * is_weightedaverageshsout,
                NA_real_
            )
        ) |>
        dplyr::mutate(
            fcf_payout = dplyr::if_else(
                !is.na(.div_total) & !is.na(cf_freecashflow) & cf_freecashflow != 0,
                .div_total / cf_freecashflow,
                NA_real_
            ),
            fcf_coverage = dplyr::if_else(
                !is.na(.div_total) & !is.na(cf_freecashflow) & cf_freecashflow != 0,
                cf_freecashflow / .div_total,
                NA_real_
            ),
            last_updated = Sys.Date()
        ) |>
        dplyr::select(
            symbol, last_updated, last_div_date,
            div_ttm, div_forward, croissance_reguliere,
            close_ref, yield,
            cagr_div_1a, cagr_div_3a, cagr_div_5a, cagr_div_10a,
            fcf_payout, fcf_coverage,
            has_special, has_irregular, last_special_date, last_irregular_date
        )

    # Écriture transactionnelle (amélioration vs TRUNCATE non transactionnel)
    table_id <- DBI::Id(schema = "stocktools", table = "dividendes_build")
    if (DBI::dbExistsTable(con, table_id)) {
        DBI::dbWithTransaction(con, {
            DBI::dbExecute(con, "TRUNCATE TABLE stocktools.dividendes_build")
            DBI::dbWriteTable(con, table_id, result, append = TRUE)
        })
    } else {
        DBI::dbWriteTable(con, table_id, result, overwrite = TRUE)
    }
    message("✔ dividendes_build : ", nrow(result), " compagnie(s).")

    invisible(result)
}

utils::globalVariables(".div_total")