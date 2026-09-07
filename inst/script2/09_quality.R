# =============================================================================
# 09_quality.R — Reconstruction quality_build (version révisée)
# =============================================================================
#
# Réécriture de l'étape 12 : reconstruction de quality_build.
# Utilise build_quality_build2() (R/10-cron_quality_build2.R) avec écriture
# transactionnelle.
#
# Variables attendues (posées par 0-plan.R) :
#   con
#   log_env (initialisé par init_log())
# =============================================================================

message("-- [9] Reconstruction quality_build --")
log_append(etape = "quality", statut = "OK", message = "Début étape quality_build")

res <- tryCatch({
    build_quality_build2(con)
    TRUE
}, error = function(e) {
    log_append("quality", "ERROR",
               message = paste0("Échec build_quality_build2 : ", conditionMessage(e)))
    message("  ✖ Échec : ", conditionMessage(e))
    FALSE
})

if (res) {
    log_append("quality", "OK", message = "quality_build reconstruite")
    message("  quality_build reconstruite.")
}
