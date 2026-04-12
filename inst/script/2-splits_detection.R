# =============================================================================
# 2-splits_detection.R — Détection des splits (mardis seulement)
# Variables attendues : con, tickers, key_fmp_api, today
# =============================================================================
message("-- [2] Détection des splits --")

if (format(today, "%u") != "2") {
  message("Pas un mardi, étape ignorée.")
} else {
  detect_and_insert_splits(tickers, con, key_fmp_api)
}
