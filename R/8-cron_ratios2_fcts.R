# 8-cron_ratios2_fcts.R — Valorisation et CAGR (version révisée)
#
# Versions v2 des fonctions de R/7-cron_ratios_fcts.R :
#   - valuation_stockprice2 : fenêtre de rolling dérivée de window_months
#     (au lieu du 375 hardcodé) + écriture transactionnelle.
#   - cagr_stockprice2 / cagr_stmts2 : écriture transactionnelle.

#' Calculer des bandes de valorisation boursière
#'
#' @description
#' Calcule des bandes de valorisation (achat, prudence, vente) à partir des
#' prix boursiers et des états financiers, en utilisant des ratios glissants
#' sur une fenêtre temporelle dérivée de `window_months`.
#'
#' Les ratios calculés sont : P/S, P/EBITDA, PE (EPS et EPS dilué).
#' Le résultat est écrit dans `valuation_build` en transaction (TRUNCATE +
#' append) : si l'écriture échoue, la table existante est préservée.
#'
#' @param con          Connexion DBI (PostgreSQL).
#' @param symbols      Vecteur de tickers à traiter.
#' @param window_months Fenêtre glissante en mois (défaut : 18). Le nombre de
#'   jours ouvrés de la fenêtre est dérivé de `window_months * 21`.
#'
#' @return Invisiblement le tibble écrit dans `valuation_build`.
#'
#' @importFrom dplyr tbl filter collect select mutate rename arrange group_by
#'   ungroup full_join if_all summarise pull all_of
#' @importFrom tidyr fill drop_na
#' @importFrom slider slide_dbl
#' @importFrom lubridate dmonths
#' @importFrom DBI dbWriteTable dbExecute dbWithTransaction dbExistsTable
#'
#' @export
valuation_stockprice2 <- function(con, symbols, window_months = 18) {

    # Fenêtre de rolling en jours ouvrés, dérivée de window_months
    n_days <- round(window_months * 21)

    message("  [1/5] Chargement des états financiers...")
    df_statement <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "financial_stmts_build")) |>
        dplyr::filter(symbol %in% !!symbols) |>
        dplyr::collect() |>
        dplyr::mutate(
            date           = as.Date(date),
            filingdate     = as.Date(filingdate),
            sales_p_share  = is_revenue  / is_weightedaverageshsout,
            ebitda_p_share = is_ebitda   / is_weightedaverageshsout
        ) |>
        dplyr::rename(
            eps     = is_eps,
            eps_dil = is_epsdiluted
        ) |>
        dplyr::select(
            date = filingdate, symbol,
            sales_p_share, ebitda_p_share, eps, eps_dil
        ) |>
        dplyr::arrange(dplyr::desc(date))

    ratio_cols <- c("sales_p_share", "ebitda_p_share", "eps", "eps_dil")

    message("  [2/3] Chargement des prix boursiers...")
    df_price <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "stockprice")) |>
        dplyr::filter(symbol %in% !!symbols) |>
        dplyr::collect() |>
        dplyr::select(symbol, date, close) |>
        dplyr::mutate(date = as.Date(date)) |>
        dplyr::arrange(dplyr::desc(date))

    message("  [3/3] Jointure prix + états et calcul des ratios...")
    df <- df_price |>
        dplyr::group_by(symbol) |>
        dplyr::full_join(df_statement, by = c("symbol", "date")) |>
        dplyr::arrange(dplyr::desc(date)) |>
        tidyr::fill(dplyr::all_of(ratio_cols), .direction = "up") |>
        dplyr::ungroup()

    # Exclure les dates antérieures à la première donnée financière disponible
    cutoff_date <- df |>
        dplyr::filter(!dplyr::if_all(dplyr::all_of(ratio_cols), is.na)) |>
        dplyr::summarise(first_date = min(date, na.rm = TRUE)) |>
        dplyr::pull(first_date)

    df <- df |>
        dplyr::filter(date >= cutoff_date - lubridate::dmonths(window_months))

    # Calcul des ratios
    df <- df |>
        dplyr::mutate(
            p_to_s      = close / sales_p_share,
            p_to_ebitda = close / ebitda_p_share,
            pe          = close / eps,
            pe_dil      = close / eps_dil
        )

    # Fonctions sécurisées : retournent NA si toute la fenêtre est NA
    safe_min <- function(x) if (all(is.na(x))) NA_real_ else min(x, na.rm = TRUE)
    safe_max <- function(x) if (all(is.na(x))) NA_real_ else max(x, na.rm = TRUE)

    # Rolling min / max — boucle par ticker pour suivre la progression
    df_clean <- df |>
        dplyr::filter(!is.na(close)) |>
        dplyr::arrange(symbol, date)

    symbols_vec <- df_clean$symbol |> unique() |> sort()
    n_total <- length(symbols_vec)
    message("  Rolling min/max sur ", n_total, " ticker(s) (étape la plus longue)...")

    df2 <- purrr::imap(
        split(df_clean, df_clean$symbol),
        \(df_sym, sym) {
            i <- which(symbols_vec == sym)
            message("    ", i, "/", n_total, " — ", sym)
            df_sym |>
                dplyr::filter(dplyr::row_number() > n_days) |>
                dplyr::mutate(
                    min_p_to_s      = slider::slide_dbl(p_to_s,      safe_min, .before = n_days),
                    max_p_to_s      = slider::slide_dbl(p_to_s,      safe_max, .before = n_days),
                    min_p_to_ebitda = slider::slide_dbl(p_to_ebitda, safe_min, .before = n_days),
                    max_p_to_ebitda = slider::slide_dbl(p_to_ebitda, safe_max, .before = n_days),
                    min_pe          = slider::slide_dbl(pe,          safe_min, .before = n_days),
                    max_pe          = slider::slide_dbl(pe,          safe_max, .before = n_days),
                    min_pe_dil      = slider::slide_dbl(pe_dil,      safe_min, .before = n_days),
                    max_pe_dil      = slider::slide_dbl(pe_dil,      safe_max, .before = n_days)
                )
        }
    ) |> dplyr::bind_rows()

    # Bandes de prix
    final <- df2 |>
        dplyr::mutate(
            buy_p_to_s      = min_p_to_s      * sales_p_share,
            sell_p_to_s     = max_p_to_s      * sales_p_share,
            caution_p_to_s  = (buy_p_to_s  + sell_p_to_s)  / 2,

            buy_p_to_ebitda     = min_p_to_ebitda * ebitda_p_share,
            sell_p_to_ebitda    = max_p_to_ebitda * ebitda_p_share,
            caution_p_to_ebitda = (buy_p_to_ebitda + sell_p_to_ebitda) / 2,

            buy_pe      = min_pe     * eps,
            sell_pe     = max_pe     * eps,
            caution_pe  = (buy_pe  + sell_pe)  / 2,

            buy_pe_dil     = min_pe_dil  * eps_dil,
            sell_pe_dil    = max_pe_dil  * eps_dil,
            caution_pe_dil = (buy_pe_dil + sell_pe_dil) / 2
        ) |>
        dplyr::select(
            symbol, date, close,
            buy_p_to_s, sell_p_to_s, caution_p_to_s,
            buy_p_to_ebitda, sell_p_to_ebitda, caution_p_to_ebitda,
            buy_pe, sell_pe, caution_pe,
            buy_pe_dil, sell_pe_dil, caution_pe_dil
        ) |>
        dplyr::arrange(symbol, dplyr::desc(date))

    final2 <- final |>
        tidyr::drop_na() |>
        dplyr::distinct(symbol, date, .keep_all = TRUE)

    # Écriture transactionnelle (amélioration vs TRUNCATE non transactionnel)
    table_id <- DBI::Id(schema = "stocktools", table = "valuation_build")
    if (DBI::dbExistsTable(con, table_id)) {
        DBI::dbWithTransaction(con, {
            DBI::dbExecute(con, "TRUNCATE TABLE stocktools.valuation_build")
            DBI::dbWriteTable(con, table_id, final2, append = TRUE)
        })
    } else {
        DBI::dbWriteTable(con, table_id, final2, overwrite = TRUE)
    }
    message(nrow(final2), " ligne(s) écrite(s) dans valuation_build.")

    invisible(final)
}

#' Calculer le CAGR du prix boursier sur plusieurs horizons
#'
#' @description
#' Pour chaque symbole, calcule le taux de croissance annuel composé (CAGR)
#' du prix de clôture sur plusieurs horizons (1, 3, 5, 10 ans). Écrit dans
#' `cagr_price_build` en transaction.
#'
#' @param con     Connexion DBI (PostgreSQL).
#' @param symbols Vecteur de tickers à traiter.
#' @param years   Vecteur d'horizons en années (défaut : `c(1, 3, 5)`).
#'
#' @return Un tibble avec une ligne par symbole et les colonnes CAGR.
#'
#' @importFrom dplyr tbl filter collect mutate select arrange slice_tail
#'   group_by group_split bind_rows
#' @importFrom lubridate years
#' @importFrom purrr map
#' @importFrom DBI dbWriteTable dbExecute dbWithTransaction dbExistsTable
#'
#' @export
cagr_stockprice2 <- function(con, symbols, years = c(1, 3, 5)) {

    df_price <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "stockprice")) |>
        dplyr::filter(symbol %in% !!symbols) |>
        dplyr::collect() |>
        dplyr::mutate(date = as.Date(date)) |>
        dplyr::select(symbol, date, close)

    compute_cagr <- function(df_sym) {
        df_sym   <- dplyr::arrange(df_sym, date)
        last_row <- dplyr::slice_tail(df_sym, n = 1)
        for (y in years) {
            target_date <- last_row$date - lubridate::years(y)
            ref_close   <- df_sym$close[which.min(abs(df_sym$date - target_date))]
            last_row[[paste0("cagr_", y, "y")]] <- (last_row$close / ref_close)^(1 / y) - 1
        }
        last_row
    }

    final <- df_price |>
        dplyr::group_by(symbol) |>
        dplyr::group_split() |>
        purrr::map(compute_cagr) |>
        dplyr::bind_rows()

    table_id <- DBI::Id(schema = "stocktools", table = "cagr_price_build")
    if (DBI::dbExistsTable(con, table_id)) {
        DBI::dbWithTransaction(con, {
            DBI::dbExecute(con, "TRUNCATE TABLE stocktools.cagr_price_build")
            DBI::dbWriteTable(con, table_id, final, append = TRUE)
        })
    } else {
        DBI::dbWriteTable(con, table_id, final, overwrite = TRUE)
    }
    message(nrow(final), " ligne(s) écrite(s) dans cagr_price_build.")

    invisible(final)
}

#' Calculer le CAGR des états financiers sur plusieurs horizons
#'
#' @description
#' Pour chaque symbole, calcule le CAGR de colonnes de `financial_stmts_build`
#' sur 1, 3, 5 et 10 ans. Le calcul est effectué par période (`period2`) pour
#' comparer des données comparables (FY vs FY, Q1 vs Q1). Seule la dernière
#' ligne par symbole est conservée. Écrit dans `cagr_stmts_build` en transaction.
#'
#' @param con     Connexion DBI (PostgreSQL).
#' @param symbols Vecteur de tickers à traiter.
#' @param cols    Vecteur de colonnes à analyser.
#'
#' @return Un tibble avec une ligne par symbole et les colonnes CAGR.
#'
#' @importFrom dplyr tbl filter collect mutate if_else arrange group_by
#'   ungroup slice_head select starts_with any_of desc
#' @importFrom purrr reduce
#' @importFrom rlang sym
#' @importFrom DBI dbWriteTable dbExecute dbWithTransaction dbExistsTable
#'
#' @export
cagr_stmts2 <- function(con, symbols,
                        cols = c("is_revenue", "is_ebitda", "is_netincome",
                                 "is_epsdiluted", "is_weightedaverageshsout",
                                 "is_weightedaverageshsoutdil", "bs_totalassets",
                                 "bs_totalliabilities", "cf_freecashflow", "caf")) {

    df <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "financial_stmts_build")) |>
        dplyr::filter(symbol %in% !!symbols) |>
        dplyr::collect() |>
        dplyr::mutate(
            date    = as.Date(date),
            period2 = dplyr::if_else(period == "FY", "Q4", period)
        )

    add_cagr <- function(df, col) {
        col_sym <- rlang::sym(col)
        df |>
            dplyr::mutate(
                !!paste0("cagr_1_",  col) := dplyr::if_else(
                    date != max(date), NA_real_,
                    !!col_sym / dplyr::lag(!!col_sym, 1) - 1),
                !!paste0("cagr_3_",  col) := dplyr::if_else(
                    date != max(date), NA_real_,
                    (!!col_sym / dplyr::lag(!!col_sym, 3))^(1/3) - 1),
                !!paste0("cagr_5_",  col) := dplyr::if_else(
                    date != max(date), NA_real_,
                    (!!col_sym / dplyr::lag(!!col_sym, 5))^(1/5) - 1),
                !!paste0("cagr_10_", col) := dplyr::if_else(
                    date != max(date), NA_real_,
                    (!!col_sym / dplyr::lag(!!col_sym, 10))^(1/10) - 1)
            )
    }

    df_grouped <- df |>
        dplyr::group_by(symbol, period2) |>
        dplyr::arrange(date)

    final <- purrr::reduce(cols, add_cagr, .init = df_grouped) |>
        dplyr::ungroup() |>
        dplyr::arrange(dplyr::desc(date)) |>
        dplyr::group_by(symbol) |>
        dplyr::slice_head(n = 1) |>
        dplyr::ungroup() |>
        dplyr::select(
            date, symbol, period,
            dplyr::any_of(cols),
            dplyr::starts_with("cagr_")
        )

    table_id <- DBI::Id(schema = "stocktools", table = "cagr_stmts_build")
    if (DBI::dbExistsTable(con, table_id)) {
        DBI::dbWithTransaction(con, {
            DBI::dbExecute(con, "TRUNCATE TABLE stocktools.cagr_stmts_build")
            DBI::dbWriteTable(con, table_id, final, append = TRUE)
        })
    } else {
        DBI::dbWriteTable(con, table_id, final, overwrite = TRUE)
    }
    message(nrow(final), " ligne(s) écrite(s) dans cagr_stmts_build.")

    invisible(final)
}