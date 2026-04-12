# =============================================================================
# 4-earnings_calendar.R — Mise à jour du calendrier de publications (mardis seulement)
# Variables attendues : con, tickers, key_fmp_api, today
# =============================================================================
message("-- [4] Calendrier de publications --")

if (format(today, "%u") != "2") {
  message("Pas un mardi, étape ignorée.")
} else {

  save_path <- "data/cies_order.rds"

  from <- format(today - 5, "%Y-%m-%d")  # ~2 mois en arrière
  to   <- format(today + 15, "%Y-%m-%d")  # ~1 mois en avant

  earnings <- fmp_get_earnings_calendar(from, to, key_fmp_api)

  if (is.null(earnings) || nrow(earnings) == 0) {
    message("Aucune publication retournée par FMP.")
  } else {

    earnings_filtered <- earnings |>
      dplyr::filter(symbol %in% tickers) |>
      dplyr::arrange(date)

#    init_cies_order(earnings_filtered, save_path)
    update_cies_order(earnings_filtered, save_path)
  }
}
