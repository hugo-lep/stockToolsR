# =============================================================================
# 8-dividends.R — Mise à jour des dividendes
# Variables attendues : con, tickers, today, key_fmp_api
# =============================================================================
message("-- [8] Mise à jour des dividendes --")

# --- Exclure les compagnies qui n'ont jamais versé de dividendes ---
# (colonne lastdividend dans cies_profile_orig, 0 ou NA = jamais de dividende)
tickers_avec_div <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "cies_profile_orig")) |>
  dplyr::filter(symbol %in% tickers, !is.na(lastdividend), lastdividend > 0) |>
  dplyr::pull(symbol)

if (length(tickers_avec_div) == 0) {
  message("Aucun ticker avec dividendes dans le scope.")
} else {
  message(length(tickers_avec_div), " ticker(s) avec dividendes à vérifier.")
  update_dividendes(con, tickers_avec_div, config_global$finance$key_fmp_api)
}
