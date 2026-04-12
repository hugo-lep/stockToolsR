# =============================================================================
# 6-statements_check.R — Vérification post-import des états financiers
# Variables attendues : con, tickers, today
# =============================================================================
message("-- [6] Vérification des états financiers --")

save_path  <- "data/cies_order.rds"
cies_order <- s3db::s3readRDS_HL(save_path)

to_check <- cies_order |>
  dplyr::filter(
    symbol         %in% tickers,
    reportDate_mod <= today
  )

if (nrow(to_check) == 0) {
  message("Aucune compagnie à vérifier aujourd'hui.")
} else {
  message("Vérification de ", nrow(to_check), " compagnie(s)...")

  for (i in seq_len(nrow(to_check))) {

    sym           <- to_check$symbol[i]
    expected_date <- to_check$reportDate[i]

    statuses <- check_filing_exists(con, sym, expected_date, tolerance_days = 7)

    cies_order <- cies_order |>
      dplyr::mutate(
        inc_status = dplyr::if_else(symbol == sym, statuses$inc_status, inc_status),
        bs_status  = dplyr::if_else(symbol == sym, statuses$bs_status,  bs_status),
        cf_status  = dplyr::if_else(symbol == sym, statuses$cf_status,  cf_status),
        reportDate_mod = dplyr::if_else(
          symbol == sym &
            (statuses$inc_status == "incomplete" |
             statuses$bs_status  == "incomplete" |
             statuses$cf_status  == "incomplete"),
          reportDate_mod + 3L,
          reportDate_mod
        )
      )

    if (all(unlist(statuses) == "complete")) {
      message("  ", sym, " : complet")
    } else {
      message("  ", sym, " : incomplet — prochain essai le ",
              cies_order$reportDate_mod[cies_order$symbol == sym])
    }
  }

  # retirer les compagnies complètes
  cies_order <- cies_order |>
    dplyr::filter(
      !(inc_status == "complete" & bs_status == "complete" & cf_status == "complete")
    )

  s3db::s3saveRDS_HL(cies_order, save_path)
  message(nrow(cies_order), " compagnie(s) restante(s) dans cies_order.")
}
