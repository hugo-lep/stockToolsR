# =============================================================================
# 08_divbuild.R — Reconstruction dividendes_build (version révisée)
# =============================================================================
#
# Réécriture de l'étape 11 : reconstruction de dividendes_build.
# Utilise build_dividendes_build2() (R/9-cron_dividendbuild2_fcts.R) avec
# écriture transactionnelle.
#
# Variables attendues (posées par 0-plan.R) :
#   con
#   log_env (initialisé par init_log())
# =============================================================================

message("-- [8] Reconstruction dividendes_build --")
log_append(etape = "divbuild", statut = "OK", message = "Début étape dividendes_build")

res <- tryCatch({
    build_dividendes_build2(con)
    TRUE
}, error = function(e) {
    log_append("divbuild", "ERROR",
               message = paste0("Échec build_dividendes_build2 : ", conditionMessage(e)))
    message("  ✖ Échec : ", conditionMessage(e))
    FALSE
})

if (res) {
    log_append("divbuild", "OK", message = "dividendes_build reconstruite")
    message("  dividendes_build reconstruite.")
}