# =============================================================================
# 11-dividend_build.R — Reconstruction de dividendes_build
#
# Calcule pour chaque symbol :
#   - Dividende TTM et forward (hors Special/Irregular)
#   - Yield estimé (div_forward / close)
#   - CAGR dividendes 1, 3, 5 et 10 ans
#   - Drapeaux has_special et has_irregular
#
# Variables disponibles depuis 0-plan.R : con, today
# =============================================================================

message("\n=== Étape 11 : dividendes_build ===")

build_dividendes_build(con)
