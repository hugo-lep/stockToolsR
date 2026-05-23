# =============================================================================
# 5-statements_import.R — Import des états financiers
# Variables attendues : con, tickers, key_fmp_api, today
# =============================================================================
message("-- [5] Import des états financiers --")

save_path <- "data/cies_order.rds"

# --- Tickers déjà présents dans la base ---
tickers_in_db <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "qts_income_stmts_orig")) |>
  dplyr::distinct(symbol) |>
  dplyr::collect() |>
  dplyr::pull(symbol)

# --- Cas 1 : nouvelles compagnies ou post-split (absentes de la DB) ---
tickers_new <- setdiff(tickers, tickers_in_db)

if (length(tickers_new) > 0) {
  message(length(tickers_new), " nouveau(x) ticker(s) à importer : ",
          paste(tickers_new, collapse = ", "))

  for (sym in tickers_new) {
    message("  Import complet : ", sym)
    tryCatch({
      df <- fmp_get_stmts_new_cie(sym, key_fmp_api, limit = 12)
      fmp_original_stmts_update(df, con)
    }, error = function(e) {
      message("  Erreur pour ", sym, " : ", e$message)
    })
    Sys.sleep(1.2)
  }
} else {
  message("Aucune nouvelle compagnie à importer.")
}

# --- Cas 2 : publications prévues (dans cies_order) ---
cies_order <- s3db::s3readRDS_HL(save_path)

tickers_to_update <- cies_order |>
  dplyr::filter(
    symbol         %in% tickers,
    symbol         %in% tickers_in_db,   # exclut les nouveaux déjà traités au cas 1
    reportDate_mod <= today
  ) |>
  dplyr::pull(symbol)

if (length(tickers_to_update) == 0) {
  message("Aucune publication prévue aujourd'hui.")
} else {
  message(length(tickers_to_update), " publication(s) à mettre à jour : ",
          paste(tickers_to_update, collapse = ", "))

  for (sym in tickers_to_update) {
    message("  Import récent : ", sym)
    tryCatch({
      df <- fmp_get_stmts_new_cie(sym, key_fmp_api, limit = 4)
      fmp_original_stmts_update(df, con, replace = TRUE)
    }, error = function(e) {
      message("  Erreur pour ", sym, " : ", e$message)
    })
    Sys.sleep(1.2)
  }
}
