# =============================================================================
# 12-quality_ratios.R — Reconstruction de quality_build
#
# Pré-calcule pour chaque symbol l'ensemble des ratios de qualité
# (rentabilité, marges, solidité, valorisation, buy ratios, CAGR)
# en joignant financial_stmts_build, valuation_build, cagr_stmts_build
# et cies_profile_build.
#
# Les métriques de dividendes restent dans dividendes_build (étape 11).
#
# Variables disponibles depuis 0-plan.R : con, today
# =============================================================================

message("\n=== Étape 12 : quality_build ===")

# ── Construction ──────────────────────────────────────────────────────────────
build_quality_build(con)
