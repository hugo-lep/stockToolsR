# =============================================================================
# 07_valcagr.R — Valorisation et CAGR (version révisée)
# =============================================================================
#
# Réécriture de l'étape 10 : bandes de valorisation et CAGR.
# Utilise les versions v2 (R/8-cron_ratios2_fcts.R) :
#   - valuation_stockprice2 : bandes P/S, P/EBITDA, PE (fenêtre = window_months)
#   - cagr_stockprice2      : CAGR du prix (1, 3, 5, 10 ans)
#   - cagr_stmts2           : CAGR des états financiers
#
# Variables attendues (posées par 0-plan.R) :
#   con, tickers
#   log_env (initialisé par init_log())
# =============================================================================

message("-- [7] Valorisation et CAGR --")
log_append(etape = "valcagr", statut = "OK", message = "Début étape valorisation/CAGR")

# --- Bandes de valorisation (P/S, P/EBITDA, PE) ---
res1 <- tryCatch({
    valuation_stockprice2(con, tickers, window_months = 18)
    TRUE
}, error = function(e) {
    log_append("valcagr", "ERROR",
               message = paste0("Échec valuation_stockprice2 : ", conditionMessage(e)))
    message("  ✖ Échec bandes de valorisation : ", conditionMessage(e))
    FALSE
})

# --- CAGR des prix boursiers ---
res2 <- tryCatch({
    cagr_stockprice2(con, tickers, years = c(1, 3, 5, 10))
    TRUE
}, error = function(e) {
    log_append("valcagr", "ERROR",
               message = paste0("Échec cagr_stockprice2 : ", conditionMessage(e)))
    message("  ✖ Échec CAGR prix : ", conditionMessage(e))
    FALSE
})

# --- CAGR des états financiers ---
res3 <- tryCatch({
    cagr_stmts2(con, tickers)
    TRUE
}, error = function(e) {
    log_append("valcagr", "ERROR",
               message = paste0("Échec cagr_stmts2 : ", conditionMessage(e)))
    message("  ✖ Échec CAGR états : ", conditionMessage(e))
    FALSE
})

if (res1 && res2 && res3) {
    log_append("valcagr", "OK", message = "Valorisation et CAGR mis à jour")
    message("  Valorisation et CAGR mis à jour.")
}