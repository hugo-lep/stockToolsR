# =============================================================================
# 3-splits_processing.R — Traitement des splits pending
# Variables attendues : con, today
# =============================================================================
message("-- [3] Traitement des splits pending --")

pending <- get_pending_splits(con, horizon_days = 0)

if (nrow(pending) == 0) {
  message("Aucun split à traiter.")
} else {
  message(nrow(pending), " split(s) à traiter.")

  for (i in seq_len(nrow(pending))) {

    sym        <- pending$symbol[i]
    split_date <- pending$split_date[i]

    message("  Nettoyage : ", sym, " (split du ", split_date, ")")

    tryCatch({
      tables <- c(
        "qts_income_stmts_orig",
        "qts_balance_stmts_orig",
        "qts_cf_stmts_orig",
        "fy_income_stmts_orig",
        "fy_balance_stmts_orig",
        "fy_cf_stmts_orig",
        "stockprice",
        "dividendes"
      )

      for (tbl in tables) {
        DBI::dbExecute(
          con,
          paste0("DELETE FROM ", tbl, " WHERE symbol = $1"),
          params = list(sym)
        )
      }

      confirm_split(con, sym, split_date, notes = "Nettoyage effectué via cron")

    }, error = function(e) {
      message("  Erreur pour ", sym, " : ", e$message)
      fail_split(con, sym, split_date, notes = e$message)
    })
  }
}
