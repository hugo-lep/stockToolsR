#' Calculer les métriques de dividendes pour un seul symbol
#'
#' @description
#' Fonction interne utilisée par `build_dividendes_build()`. Pour un tibble
#' de dividendes d'un seul symbol (trié par date décroissante), calcule :
#' - Dividende annualisé TTM (hors Special/Irregular)
#' - Dividende forward (TTM × (1 + cagr_1a) si croissance régulière)
#' - CAGR dividendes 1, 3, 5 et 10 ans
#' - Drapeaux Special et Irregular
#'
#' @param df_sym Tibble filtré sur un seul symbol, colonnes `date`,
#'   `adjdividend`, `frequency`.
#'
#' @return Tibble d'une ligne avec toutes les métriques du symbol.
#'
#' @noRd
.calc_div_symbol <- function(df_sym) {

    df_all <- dplyr::arrange(df_sym, dplyr::desc(date))

    # Dividendes réguliers seulement (exclusion Special et Irregular)
    df_reg <- df_all |>
        dplyr::filter(!frequency %in% c("Special", "Irregular"))

    # TTM (trailing 12 mois)
    if (nrow(df_reg) == 0) {
        # Aucun dividende régulier : retourner une ligne NA
        return(tibble::tibble(
            symbol               = df_sym$symbol[1],
            last_div_date        = as.Date(NA),
            div_ttm              = NA_real_,
            div_forward          = NA_real_,
            croissance_reguliere = FALSE,
            cagr_div_1a          = NA_real_,
            cagr_div_3a          = NA_real_,
            cagr_div_5a          = NA_real_,
            cagr_div_10a         = NA_real_,
            has_special          = any(df_all$frequency == "Special",   na.rm = TRUE),
            has_irregular        = any(df_all$frequency == "Irregular", na.rm = TRUE),
            last_special_date    = as.Date(NA),
            last_irregular_date  = as.Date(NA)
        ))
    }

    max_date <- max(df_reg$date, na.rm = TRUE)
    div_ttm  <- sum(
        df_reg$adjdividend[df_reg$date >= max_date - lubridate::years(1)],
        na.rm = TRUE
    )

    # Paiements par année selon la fréquence dominante
    freq_dominante <- df_reg$frequency[1]
    n <- switch(freq_dominante,
        "Quarterly"   = 4L,
        "Semi-Annual" = 2L,
        "Annual"      = 1L,
        "Monthly"     = 12L,
        "Weekly"      = 52L,
        4L   # défaut si fréquence inconnue
    )

    # Somme de N versements à un décalage d'offset années (positionnelle)
    annual_at <- function(offset) {
        idx <- seq(offset * n + 1L, (offset + 1L) * n)
        idx <- idx[idx <= nrow(df_reg)]
        if (length(idx) < n) return(NA_real_)
        sum(df_reg$adjdividend[idx], na.rm = TRUE)
    }

    da0  <- annual_at(0)    # annualisé actuel
    da1  <- annual_at(1)    # il y a 1 an
    da3  <- annual_at(3)    # il y a 3 ans
    da5  <- annual_at(5)    # il y a 5 ans
    da10 <- annual_at(10)   # il y a 10 ans

    # CAGR
    cagr_1a  <- if (!anyNA(c(da0, da1))  && da1  > 0) da0 / da1  - 1            else NA_real_
    cagr_3a  <- if (!anyNA(c(da0, da3))  && da3  > 0) (da0 / da3)^(1/3)  - 1   else NA_real_
    cagr_5a  <- if (!anyNA(c(da0, da5))  && da5  > 0) (da0 / da5)^(1/5)  - 1   else NA_real_
    cagr_10a <- if (!anyNA(c(da0, da10)) && da10 > 0) (da0 / da10)^(1/10) - 1  else NA_real_

    # Croissance régulière ?
    # Critère : cagr_1a et cagr_3a tous deux >= 0 et écart < 10 points
    regulier <- !anyNA(c(cagr_1a, cagr_3a)) &&
                cagr_1a >= 0 &&
                cagr_3a >= 0 &&
                abs(cagr_1a - cagr_3a) < 0.10

    div_forward <- if (regulier && !is.na(cagr_1a))
                       div_ttm * (1 + cagr_1a)
                   else
                       div_ttm

    # Drapeaux Special / Irregular
    has_special   <- any(df_all$frequency == "Special",   na.rm = TRUE)
    has_irregular <- any(df_all$frequency == "Irregular", na.rm = TRUE)

    last_special   <- if (has_special)
        max(df_all$date[df_all$frequency == "Special"],   na.rm = TRUE)
    else
        as.Date(NA)

    last_irregular <- if (has_irregular)
        max(df_all$date[df_all$frequency == "Irregular"], na.rm = TRUE)
    else
        as.Date(NA)

    tibble::tibble(
        symbol               = df_sym$symbol[1],
        last_div_date        = max_date,
        div_ttm              = div_ttm,
        div_forward          = div_forward,
        croissance_reguliere = regulier,
        cagr_div_1a          = cagr_1a,
        cagr_div_3a          = cagr_3a,
        cagr_div_5a          = cagr_5a,
        cagr_div_10a         = cagr_10a,
        has_special          = has_special,
        has_irregular        = has_irregular,
        last_special_date    = last_special,
        last_irregular_date  = last_irregular
    )
}


#' Reconstruire la table `dividendes_build`
#'
#' @description
#' Pour chaque symbol présent dans la table `dividendes`, calcule les
#' métriques de dividendes (TTM, forward, CAGR 1/3/5/10 ans, yield,
#' drapeaux Special/Irregular, ratios FCF) et écrit le résultat dans
#' `dividendes_build`.
#'
#' Le prix de référence (`close_ref`) est lu depuis `valuation_build`
#' (dernière valeur par symbol). Le yield est calculé comme
#' `div_forward / close_ref`.
#'
#' Les ratios FCF sont calculés à partir de `financial_stmts_build`
#' (dernière période par symbol) :
#' - `fcf_payout`   = (div_ttm × actions) / cf_freecashflow
#' - `fcf_coverage` = cf_freecashflow / (div_ttm × actions)
#'
#' Calculés uniquement si div_ttm > 0 et cf_freecashflow ≠ 0.
#' Un FCF négatif produit un payout négatif (dividende non couvert).
#'
#' Les dividendes de type `"Special"` et `"Irregular"` sont exclus du
#' calcul du TTM et des CAGR, mais signalés via `has_special` et
#' `has_irregular`.
#'
#' @param con Connexion DBI active (PostgreSQL)
#'
#' @return Invisiblement le tibble écrit dans `dividendes_build`.
#'
#' @importFrom dplyr arrange desc filter mutate select left_join rename
#'   group_by group_split bind_rows if_else
#' @importFrom DBI dbReadTable dbGetQuery dbExecute dbWriteTable
#' @importFrom lubridate years
#' @importFrom purrr map
#' @importFrom tibble tibble
#'
#' @export
#'
#' @examples
#' \dontrun{
#' build_dividendes_build(con)
#' }
build_dividendes_build <- function(con) {

    message("  [1/5] Chargement des dividendes...")
    dividendes <- DBI::dbReadTable(
        con,
        DBI::Id(schema = "stocktools", table = "dividendes")
    ) |>
        dplyr::mutate(date = as.Date(date))

    message("  [2/5] Chargement des prix de référence (valuation_build)...")
    close_df <- DBI::dbGetQuery(con, "
    SELECT DISTINCT ON (symbol) symbol, close
    FROM stocktools.valuation_build
    ORDER BY symbol, date DESC
  ")

    message("  [3/5] Chargement FCF et actions (financial_stmts_build)...")
    fcf_df <- DBI::dbGetQuery(con, "
    SELECT DISTINCT ON (symbol)
      symbol, cf_freecashflow, is_weightedaverageshsout
    FROM stocktools.financial_stmts_build
    ORDER BY symbol, date DESC
  ")

    message("  [4/5] Calcul des métriques par symbol...")
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
            # Total dividendes versés = dividende par action × nombre d'actions
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

    message("  [5/5] Écriture dans dividendes_build (", nrow(result), " lignes)...")
    DBI::dbExecute(con, "TRUNCATE TABLE stocktools.dividendes_build")
    DBI::dbWriteTable(
        conn   = con,
        name   = DBI::Id(schema = "stocktools", table = "dividendes_build"),
        value  = result,
        append = TRUE
    )
    message("✔ dividendes_build : ", nrow(result), " compagnie(s).")

    invisible(result)
}

utils::globalVariables(".div_total")
