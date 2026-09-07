# =============================================================================
# 02_splits.R — Détection et traitement des splits (version révisée)
# =============================================================================
#
# Réécriture (fusion) des étapes 2 (détection, mardis) et 3 (traitement)
# du cron des splits.
#
# Phase A — Détection (mardis seulement) : appelle le calendrier des splits
#   FMP sur ±10 jours, filtre sur les tickers du S&P 500, calcule le ratio
#   et insère les splits en statut `pending` dans `split_log`.
#
# Phase B — Traitement (toujours) : pour chaque split pending dont la date
#   est passée, supprime les données du symbol (états financiers, prix,
#   dividendes) afin que les étapes suivantes les re-téléchargent.
#
# Utilise le helper DRY fmp_get() (R/0-api_fcts.R) et les fonctions du
# package : get_pending_splits(), confirm_split(), fail_split().
#
# Variables attendues (posées par 0-plan.R) :
#   con, tickers, key_fmp_api, today
#   log_env (initialisé par init_log())
#
# Dépend de : R/0-api_fcts.R (chargé par devtools::load_all())
# =============================================================================

message("-- [2] Détection et traitement des splits --")
log_append(etape = "splits", statut = "OK", message = "Début étape splits")

# ---------------------------------------------------------------------------
# Phase A — Détection des splits (mardis seulement)
# ---------------------------------------------------------------------------
if (format(today, "%u") == "2") {

    message("  Détection des splits (mardi)")

    from <- format(today - 10, "%Y-%m-%d")
    to   <- format(today + 10, "%Y-%m-%d")

    splits_raw <- fmp_get(
        endpoint    = "splits-calendar",
        params      = list(from = from, to = to),
        key_fmp_api = key_fmp_api
    )

    if (is.null(splits_raw) || nrow(splits_raw) == 0) {
        message("  Aucun split retourné par FMP.")
        log_append("splits", "OK", message = "Aucun split retourné par FMP")
    } else {
        splits <- splits_raw |>
            dplyr::filter(symbol %in% tickers) |>
            dplyr::mutate(
                split_ratio = numerator / denominator,
                split_date  = as.Date(date)
            ) |>
            dplyr::select(symbol, split_date, split_ratio)

        if (nrow(splits) == 0) {
            message("  Aucun split détecté pour les tickers S&P 500.")
            log_append("splits", "OK", message = "Aucun split pour le S&P 500")
        } else {
            message("  ", nrow(splits), " split(s) détecté(s) : ",
                    paste(splits$symbol, collapse = ", "))

            for (i in seq_len(nrow(splits))) {
                DBI::dbExecute(
                    con, "
                    INSERT INTO stocktools.split_log
                      (symbol, split_date, split_ratio, status, detected_date)
                    VALUES ($1, $2, $3, 'pending', CURRENT_DATE)
                    ON CONFLICT (symbol, split_date) DO NOTHING;
                    ",
                    params = list(
                        splits$symbol[i],
                        as.character(splits$split_date[i]),
                        splits$split_ratio[i]
                    )
                )
                log_append("splits", "OK", splits$symbol[i],
                           message = paste0("Split détecté (", splits$split_date[i],
                                            ", ratio ", splits$split_ratio[i], ")"))
            }
        }
    }
} else {
    message("  Pas un mardi, détection ignorée.")
    log_append("splits", "OK", message = "Pas un mardi, détection ignorée")
}

# ---------------------------------------------------------------------------
# Phase B — Traitement des splits pending
# ---------------------------------------------------------------------------
pending <- get_pending_splits(con, horizon_days = -1)

if (nrow(pending) == 0) {
    message("  Aucun split à traiter.")
    log_append("splits", "OK", message = "Aucun split à traiter")
} else {
    message("  ", nrow(pending), " split(s) à traiter.")

    tables_a_nettoyer <- c(
        "qts_income_stmts_orig", "qts_balance_stmts_orig", "qts_cf_stmts_orig",
        "fy_income_stmts_orig", "fy_balance_stmts_orig", "fy_cf_stmts_orig",
        "stockprice", "dividendes"
    )

    for (i in seq_len(nrow(pending))) {

        sym        <- pending$symbol[i]
        split_date <- pending$split_date[i]

        message("  Nettoyage : ", sym, " (split du ", split_date, ")")

        # Transaction : suppression des données + mise à jour du statut
        # (tout ou rien — si confirm_split échoue, les suppressions sont annulées)
        res <- tryCatch({
            DBI::dbWithTransaction(con, {
                for (tbl in tables_a_nettoyer) {
                    DBI::dbExecute(
                        con,
                        paste0("DELETE FROM stocktools.", tbl, " WHERE symbol = $1"),
                        params = list(sym)
                    )
                }
                confirm_split(con, sym, split_date, notes = "Nettoyage effectué via cron")
            })
            TRUE
        }, error = function(e) {
            log_append("splits", "ERROR", sym,
                       paste0("Échec nettoyage split : ", conditionMessage(e)))
            fail_split(con, sym, split_date, notes = conditionMessage(e))
            FALSE
        })

        if (res) {
            log_append("splits", "OK", sym,
                       message = paste0("Split traité (", split_date, ")"))
        }
    }
}