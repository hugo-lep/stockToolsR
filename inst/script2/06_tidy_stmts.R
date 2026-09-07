# =============================================================================
# 06_tidy_stmts.R — Reconstruction financial_stmts_build (version révisée)
# =============================================================================
#
# Réécriture de l'étape 9 : reconstruction de financial_stmts_build en TTM.
# Utilise tidy_stmts2() (R/7-cron_tidy_stmts2_fcts.R) qui reproduit la logique
# TTM de tidy_stmts() avec une écriture transactionnelle.
#
# Variables attendues (posées par 0-plan.R) :
#   con
#   log_env (initialisé par init_log())
# =============================================================================

message("-- [6] Reconstruction financial_stmts_build --")
log_append(etape = "tidy_stmts", statut = "OK", message = "Début étape tidy_stmts")

# Colonnes générales (présentes dans les 3 états financiers)
keep_cols_gen <- c(
    "date", "symbol", "reportedcurrency", "cik",
    "filingdate", "accepteddate", "fiscalyear", "period"
)

# Colonnes income statement
keep_cols_is <- c(
    "revenue", "grossprofit", "interestincome", "interestexpense",
    "depreciationandamortization", "ebitda", "ebit", "operatingincome",
    "netincome", "eps", "epsdiluted",
    "weightedaverageshsout", "weightedaverageshsoutdil"
)

# Colonnes balance sheet
keep_cols_bs <- c(
    "totalcurrentassets", "totalnoncurrentassets", "totalassets",
    "totalcurrentliabilities", "totalnoncurrentliabilities", "totalliabilities",
    "totalstockholdersequity",
    "shorttermdebt", "longtermdebt", "totaldebt"
)

# Colonnes cash flow
keep_cols_cf <- c(
    "stockbasedcompensation",
    "netcashprovidedbyoperatingactivities",
    "netcashprovidedbyinvestingactivities",
    "netcashprovidedbyfinancingactivities",
    "freecashflow"
)

res <- tryCatch({
    tidy_stmts2(con, keep_cols_gen, keep_cols_is, keep_cols_bs, keep_cols_cf)
    TRUE
}, error = function(e) {
    log_append("tidy_stmts", "ERROR",
               message = paste0("Échec reconstruction TTM : ", conditionMessage(e)))
    message("  ✖ Échec reconstruction : ", conditionMessage(e))
    FALSE
})

if (res) {
    log_append("tidy_stmts", "OK", message = "financial_stmts_build reconstruite")
    message("  financial_stmts_build reconstruite.")
}
