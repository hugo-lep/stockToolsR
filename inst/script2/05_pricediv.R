# =============================================================================
# 05_pricediv.R — Prix boursiers et dividendes (version révisée)
# =============================================================================
#
# Réécriture (fusion) des étapes 7 (prix) et 8 (dividendes).
#
# Prix : réutilise update_stockprice() du package (via tq_get / Yahoo Finance).
#   Deux cas : tickers déjà présents (delta) et nouveaux/post-split (full 12 ans).
# Dividend : réécrit avec le helper fmp_get() (calendrier pour les présents,
#   endpoint par compagnie pour les absents).
#
# Les tickers non disponibles sur Yahoo sont stockés dans un fichier .rds sur
# S3 (extensible quand on élargira le périmètre au-delà du S&P 500).
#
# Variables attendues (posées par 0-plan.R) :
#   con, tickers, key_fmp_api, today
#   log_env (initialisé par init_log())
# =============================================================================

message("-- [5] Prix boursiers et dividendes --")
log_append(etape = "pricediv", statut = "OK", message = "Début étape prix et dividendes")

# ---------------------------------------------------------------------------
# Tickers non disponibles sur Yahoo Finance (chargés depuis S3, extensibles)
# ---------------------------------------------------------------------------
non_available_path <- "stockToolsR/data/non_available_stockprice.rds"

non_available_stockprice <- tryCatch(
    s3db::s3readRDS_HL(object = non_available_path),
    error = function(e) {
        # Liste par défaut si le fichier n'existe pas encore
        defaut <- c("MRO", "SQ", "ATVI", "TWX", "TWTR", "VIAC")
        s3db::s3saveRDS_HL(value = defaut, object_name = non_available_path)
        defaut
    }
)

# ---------------------------------------------------------------------------
# PRIX — mise à jour des prix boursiers
# ---------------------------------------------------------------------------
tickers_scope <- setdiff(tickers, non_available_stockprice)

latest_market_date <- tidyquant::tq_get(
    "AAPL",
    get  = "stock.prices",
    from = today - 7,
    to   = today
) |>
    dplyr::pull(date) |>
    max()

message("  Dernière date de marché : ", latest_market_date)

stockprice_up_to_date <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "stockprice")) |>
    dplyr::filter(symbol %in% tickers_scope) |>
    dplyr::group_by(symbol) |>
    dplyr::summarise(last_date = max(date, na.rm = TRUE)) |>
    dplyr::collect() |>
    dplyr::filter(as.Date(last_date) >= latest_market_date) |>
    dplyr::pull(symbol)

symbols_to_update <- setdiff(tickers_scope, stockprice_up_to_date)

if (length(symbols_to_update) == 0) {
    message("  Tous les prix sont à jour.")
    log_append("pricediv", "OK", message = "Tous les prix sont à jour")
} else {
    message("  ", length(symbols_to_update), " ticker(s) à mettre à jour.")
    update_stockprice(con, symbols_to_update)
    log_append("pricediv", "OK",
               message = paste0(length(symbols_to_update), " ticker(s) prix mis à jour"))
}

# ---------------------------------------------------------------------------
# DIVIDENDES — mise à jour des dividendes
# ---------------------------------------------------------------------------
# Compagnies ayant déjà versé des dividendes (lastdividend > 0 dans le profil)
tickers_avec_div <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "cies_profile_orig")) |>
    dplyr::filter(symbol %in% tickers, !is.na(lastdividend), lastdividend > 0) |>
    dplyr::pull(symbol)

if (length(tickers_avec_div) == 0) {
    message("  Aucun ticker avec dividendes dans le scope.")
    log_append("pricediv", "OK", message = "Aucun ticker avec dividendes")
} else {

    message("  ", length(tickers_avec_div), " ticker(s) avec dividendes à vérifier.")

    # Tickers déjà présents vs absents de la table dividendes
    existing_symbols <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "dividendes")) |>
        dplyr::filter(symbol %in% !!tickers_avec_div) |>
        dplyr::distinct(symbol) |>
        dplyr::collect() |>
        dplyr::pull(symbol)

    missing_symbols <- setdiff(tickers_avec_div, existing_symbols)

    to_date <- Sys.Date() - 1

    # Cas 1 : tickers déjà présents → calendrier FMP depuis max(date)
    if (length(existing_symbols) > 0) {
        from_date <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "dividendes")) |>
            dplyr::filter(symbol %in% !!existing_symbols) |>
            dplyr::summarise(max_date = max(date, na.rm = TRUE)) |>
            dplyr::collect() |>
            dplyr::pull(max_date) |>
            as.Date()

        df_cal <- fmp_get(
            endpoint    = "dividends-calendar",
            params      = list(from = format(from_date, "%Y-%m-%d"),
                               to   = format(to_date, "%Y-%m-%d")),
            key_fmp_api = key_fmp_api
        )

        if (!is.null(df_cal) && nrow(df_cal) > 0) {
            names(df_cal) <- tolower(names(df_cal))

            df_cal <- df_cal |>
                dplyr::mutate(date = as.Date(date)) |>
                dplyr::filter(!is.na(date), symbol %in% existing_symbols)

            existing_keys <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "dividendes")) |>
                dplyr::filter(symbol %in% !!existing_symbols) |>
                dplyr::select(symbol, date) |>
                dplyr::collect() |>
                dplyr::mutate(date = as.Date(date))

            df_to_add <- dplyr::anti_join(df_cal, existing_keys, by = c("symbol", "date")) |>
                dplyr::distinct(symbol, date, .keep_all = TRUE)

            if (nrow(df_to_add) > 0) {
                DBI::dbWriteTable(
                    con,
                    DBI::Id(schema = "stocktools", table = "dividendes"),
                    df_to_add,
                    append = TRUE
                )
                message("  ", nrow(df_to_add), " dividende(s) ajouté(s) (tickers existants).")
                log_append("pricediv", "OK",
                           message = paste0(nrow(df_to_add), " dividende(s) ajouté(s)"))
            } else {
                message("  Aucun nouveau dividende pour les tickers existants.")
            }
        }
    }

    # --- Cas 2 : tickers absents → historique par compagnie (12 ans) ---
    if (length(missing_symbols) > 0) {
        message("  Import complet dividendes pour ", length(missing_symbols),
                " nouveau(x) ticker(s).")

        results <- purrr::map(missing_symbols, \(sym) {
            Sys.sleep(0.2)
            df <- fmp_get(
                endpoint    = "dividends",
                params      = list(symbol = sym, limit = 500),
                key_fmp_api = key_fmp_api
            )
            if (is.null(df) || nrow(df) == 0) return(NULL)
            names(df) <- tolower(names(df))
            df |>
                dplyr::mutate(date = as.Date(date)) |>
                dplyr::filter(!is.na(date))
        })

        df_new <- dplyr::bind_rows(results)

        if (nrow(df_new) > 0) {
            existing_keys_new <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "dividendes")) |>
                dplyr::filter(symbol %in% !!missing_symbols) |>
                dplyr::select(symbol, date) |>
                dplyr::collect() |>
                dplyr::mutate(date = as.Date(date))

            df_to_add <- dplyr::anti_join(df_new, existing_keys_new, by = c("symbol", "date")) |>
                dplyr::distinct(symbol, date, .keep_all = TRUE)

            if (nrow(df_to_add) > 0) {
                DBI::dbWriteTable(
                    con,
                    DBI::Id(schema = "stocktools", table = "dividendes"),
                    df_to_add,
                    append = TRUE
                )
                message("  ", nrow(df_to_add), " dividende(s) ajouté(s) pour les nouveaux.")
                log_append("pricediv", "OK",
                           message = paste0(nrow(df_to_add), " dividende(s) nouveaux"))
            }
        } else {
            message("  Aucun dividende trouvé pour les nouveaux tickers.")
        }
    }
}
