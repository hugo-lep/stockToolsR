# =============================================================================
# 04_statements.R — Import et vérification des états financiers (révisé)
# =============================================================================
#
# Réécriture (fusion) des étapes 5 (import) et 6 (vérification post-import).
#
# Cas 1 — Nouvelles compagnies ou post-split (absentes de la DB) :
#   import complet (12 ans) via fmp_get().
# Cas 2 — Publications prévues dans cies_order (reportDate_mod <= today) :
#   import récent (4 derniers rapports, remplace l'existant).
# Vérification — pour chaque compagnie à traiter : check_filing_exists(),
#   mise à jour des statuts, reportDate_mod +3 si incomplet, retrait si complet.
#
# Utilise le helper DRY fmp_get() (R/0-api_fcts.R) et check_filing_exists()
# du package. L'écriture des 6 tables est faite en transaction.
#
# Variables attendues (posées par 0-plan.R) :
#   con, tickers, key_fmp_api, today
#   log_env (initialisé par init_log())
# =============================================================================

message("-- [4] Import et vérification des états financiers --")
log_append(etape = "statements", statut = "OK", message = "Début étape états financiers")

save_path <- "stockToolsR/data/cies_order.rds"

# =============================================================================
# Helpers locaux
# =============================================================================

# Récupère les 4 trimestres (Q1-Q4) + FY pour income/balance/cashflow.
# Retourne une liste de data.frames (les appels échoués sont exclus, pas NULL).
get_stmts_cie <- function(symbol, key_fmp_api, limit) {
    quarters   <- c("Q1", "Q2", "Q3", "Q4")
    statements <- c("income", "balance-sheet", "cash-flow")

    get_q <- function(type) {
        purrr::map(quarters, \(q) fmp_get(
            endpoint    = paste0(type, "-statement"),
            params      = list(symbol = symbol, limit = limit, period = q),
            key_fmp_api = key_fmp_api
        )) |> purrr::compact()
    }

    get_fy <- function(type) {
        fmp_get(
            endpoint    = paste0(type, "-statement"),
            params      = list(symbol = symbol, limit = limit, period = "FY"),
            key_fmp_api = key_fmp_api
        )
    }

    list(
        income   = get_q("income"),
        balance  = get_q("balance-sheet"),
        cashflow = get_q("cash-flow"),
        annual   = list(
            get_fy("income"), get_fy("balance-sheet"), get_fy("cash-flow")
        )
    )
}

# Écrit les 6 tables *_orig en transaction (remplacement ou ajout).
write_stmts_tables <- function(con, df, replace = FALSE) {

    tables <- list(
        list(df = dplyr::bind_rows(df$income),   name = "qts_income_stmts_orig"),
        list(df = dplyr::bind_rows(df$balance),  name = "qts_balance_stmts_orig"),
        list(df = dplyr::bind_rows(df$cashflow), name = "qts_cf_stmts_orig"),
        list(df = df$annual[[1]],                name = "fy_income_stmts_orig"),
        list(df = df$annual[[2]],                name = "fy_balance_stmts_orig"),
        list(df = df$annual[[3]],                name = "fy_cf_stmts_orig")
    )

    DBI::dbWithTransaction(con, {
        for (t in tables) {
            if (is.null(t$df) || nrow(t$df) == 0) next
            df_clean <- t$df |>
                dplyr::mutate(date = lubridate::ymd(date))
            names(df_clean) <- tolower(names(df_clean))

            symbol_val <- unique(df_clean$symbol)[1]

            if (replace) {
                DBI::dbExecute(
                    con,
                    paste0("DELETE FROM stocktools.", t$name, " WHERE symbol = $1"),
                    params = list(symbol_val)
                )
            }
            DBI::dbWriteTable(
                con,
                DBI::Id(schema = "stocktools", table = t$name),
                df_clean,
                append = TRUE
            )
        }
    })
}

# Import complet pour un symbol (avec log).
import_complet <- function(sym, key_fmp_api, limit = 12) {
    df <- get_stmts_cie(sym, key_fmp_api, limit)
    write_stmts_tables(con, df, replace = FALSE)
    log_append("statements", "OK", sym, message = "Import complet")
    message("    ✔ ", sym, " : import complet")
}

# Import récent (publication) avec remplacement.
import_recent <- function(sym, key_fmp_api, limit = 4) {
    df <- get_stmts_cie(sym, key_fmp_api, limit)
    write_stmts_tables(con, df, replace = TRUE)
    log_append("statements", "OK", sym, message = "Import récent")
    message("    ✔ ", sym, " : import récent")
}

# =============================================================================
# Cas 1 — Nouvelles compagnies ou post-split (absentes de la DB)
# =============================================================================
tickers_in_db <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "qts_income_stmts_orig")) |>
    dplyr::distinct(symbol) |>
    dplyr::collect() |>
    dplyr::pull(symbol)

new_cies <- setdiff(tickers, tickers_in_db)

if (length(new_cies) > 0) {
    message("  ", length(new_cies), " nouveau(x) ticker(s) : ",
            paste(new_cies, collapse = ", "))
    for (sym in new_cies) {
        tryCatch(
            import_complet(sym, key_fmp_api, limit = 12),
            error = function(e) {
                log_append("statements", "ERROR", sym,
                           paste0("Échec import complet : ", conditionMessage(e)))
                message("    ✖ ", sym, " : échec import (", conditionMessage(e), ")")
            }
        )
        Sys.sleep(1.2)   # limite FMP : 300 appels/min
    }
} else {
    message("  Aucune nouvelle compagnie à importer.")
}

# ===========================================================================
# Cas 2 — Publications prévues (dans cies_order)
# ===========================================================================
cies_order <- tryCatch(
    s3db::s3readRDS_HL(object = save_path),
    error = function(e) NULL
)

if (!is.null(cies_order)) {
    to_update <- cies_order |>
        dplyr::filter(
            symbol         %in% tickers,
            symbol         %in% tickers_in_db,   # exclut les nouveaux du cas 1
            reportDate_mod <= today
        ) |>
        dplyr::pull(symbol)

    if (length(to_update) == 0) {
        message("  Aucune publication prévue aujourd'hui.")
    } else {
        message("  ", length(to_update), " publication(s) à mettre à jour : ",
                paste(to_update, collapse = ", "))
        for (sym in to_update) {
            tryCatch(
                import_recent(sym, key_fmp_api, limit = 4),
                error = function(e) {
                    log_append("statements", "ERROR", sym,
                               message = paste0("Échec import récent : ", conditionMessage(e)))
                    message("    ✗", sym, " : échec import (", conditionMessage(e), ")")
                }
            )
            Sys.sleep(1.2)
        }
    }
} else {
    message("  cies_order absent — aucun import de publications.")
}

# ===========================================================================
# Vérification post-import (mise à jour des statuts dans cies_order)
# ===========================================================================
if (!is.null(cies_order)) {
    to_check <- cies_order |>
        dplyr::filter(
            symbol %in% tickers,
            reportDate_mod <= today
        )

    if (nrow(to_check) == 0) {
        message("  Aucune compagnie à vérifier.")
    } else {
        message("  Vérification de ", nrow(to_check), " compagnie(s)...")

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
                        as.Date(Sys.Date()) + 3L,
                        reportDate_mod
                    )
                )

            if (all(unlist(statuses) == "complete")) {
                log_append("statements", "OK", sym, message = "États financiers complets")
                message("  ✔ ", sym, " : complet")
            } else {
                log_append("statements", "OK", sym, message = "Incomplet, nouvel essai +3 jours")
                message("  ", sym, " : incomplet — nouvel essai dans 3 jours")
            }
        }

        # Retirer les compagnies complètes
        cies_order <- cies_order |>
            dplyr::filter(
                !(inc_status == "complete" & bs_status == "complete" & cf_status == "complete")
            )

        s3db::s3saveRDS_HL(cies_order, save_path)
        message("  ", nrow(cies_order), " compagnie(s) restante(s) dans cies_order.")
    }
}
