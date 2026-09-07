# =============================================================================
# 03_earning_cal.R — Calendrier de publications (version révisée)
# =============================================================================
#
# Réécriture de l'étape 4 : mise à jour du calendrier de publications et du
# suivi `cies_order.rds` (mardis seulement).
#
# Le fichier `cies_order.rds` (sur S3) suit, pour chaque compagnie qui publie,
# les statuts des 3 états financiers : `inc_status`, `bs_status`, `cf_status`
# (valeurs : "pending" / "complete"). Utilisé par l'étape 5 (import).
#
# Utilise le helper DRY fmp_get() (R/0-api_fcts.R) et les fonctions du
# package : init_cies_order(), update_cies_order().
#
# Variables attendues (posées par 0-plan.R) :
#   con, tickers, key_fmp_api, today
#   log_env (initialisé par init_log())
#
# Dépend de : R/0-api_fcts.R (chargé par devtools::load_all())
# =============================================================================

message("-- [3] Calendrier de publications --")
log_append(etape = "earning_cal", statut = "OK", message = "Début étape calendrier")

if (format(today, "%u") != "2") {
    message("  Pas un mardi, étape ignorée.")
    log_append("earning_cal", "OK", message = "Pas un mardi, étape ignorée")
} else {

    save_path <- "stockToolsR/data/cies_order.rds"

    from <- format(today - 5, "%Y-%m-%d")
    to   <- format(today + 15, "%Y-%m-%d")

    earnings <- fmp_get(
        endpoint    = "earnings-calendar",
        params      = list(from = from, to = to),
        key_fmp_api = key_fmp_api
    )

    if (is.null(earnings) || nrow(earnings) == 0) {
        message("  Aucune publication retournée par FMP.")
        log_append("earning_cal", "OK", message = "Aucune publication retournée par FMP")
    } else {

        earnings_filtered <- earnings |>
            dplyr::filter(symbol %in% tickers) |>
            dplyr::arrange(date)

        # Auto init/update : initialise le suivi s'il n'existe pas encore,
        # sinon le met à jour (ajoute uniquement les nouvelles compagnies).
        existe <- tryCatch({
            s3db::s3readRDS_HL(object = save_path)
            TRUE
        }, error = function(e) FALSE)

        if (!existe) {
            message("  Initialisation du suivi cies_order (", nrow(earnings_filtered),
                    " compagnie(s)).")
            init_cies_order(earnings_filtered, save_path)
        } else {
            update_cies_order(earnings_filtered, save_path)
        }

        log_append("earning_cal", "OK",
                   message = paste0("Calendrier mis à jour (", nrow(earnings_filtered),
                                    " compagnies)"))
    }
}
