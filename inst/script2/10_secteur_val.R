# =============================================================================
# 10_secteur_val.R — Valorisation sectorielle (phase de test / prototypage)
# =============================================================================
#
# Objectif : produire une série temporelle de ratios sectoriels médians
# (P/E, P/S, P/EBITDA) sur lesquels on pourra tracer des bandes
# buy/sell/caution, comme le graphique check_price de mod_finance6 mais au
# niveau secteur.
#
# NOTE : ce script N'ÉCRIT PAS en base. Il agrège des données déjà disponibles
# et écrit le résultat dans un .rds local (inst/script2/) pour validation.
# Si le résultat est satisfaisant, on pourra l'encapsuler dans une fonction
# R/ et créer une table sector_valuation_build dédiée.
#
# Sources :
#   - financial_stmts_build : par-share (is_revenue, is_ebitda,
#     is_epsdiluted, is_weightedaverageshsout) par date
#   - stockprice            : close par date
#   - cies_profile_build    : mapping symbol → sector
#
# Variables attendues (posées par 0-plan.R) :
#   con, log_env (initialisé par init_log())
# =============================================================================

message("-- [10] Valorisation sectorielle (test) --")

# Fenêtre de rolling en jours ouvrés (même convention que valuation_stockprice2)
window_months <- 18
n_days        <- round(window_months * 21)

# ---------------------------------------------------------------------------
# [1/3] Chargement des par-share et du prix
# ---------------------------------------------------------------------------
message("  [1/3] Chargement des états financiers (par-share)...")
df_statement <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "financial_stmts_build")) |>
    dplyr::select(
        date, symbol, filingdate,
        is_revenue, is_ebitda, is_epsdiluted, is_weightedaverageshsout
    ) |>
    dplyr::collect() |>
    dplyr::mutate(
        date       = as.Date(date),
        filingdate = as.Date(filingdate),
        sales_p_share  = is_revenue  / is_weightedaverageshsout,
        ebitda_p_share = is_ebitda   / is_weightedaverageshsout
    ) |>
    dplyr::rename(eps = is_epsdiluted) |>
    dplyr::select(date = filingdate, symbol, sales_p_share, ebitda_p_share, eps) |>
    dplyr::arrange(dplyr::desc(date))

ratio_cols <- c("sales_p_share", "ebitda_p_share", "eps")

message("  [1/3] Chargement du prix boursier...")
df_price <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "stockprice")) |>
    dplyr::select(symbol, date, close) |>
    dplyr::collect() |>
    dplyr::mutate(date = as.Date(date)) |>
    dplyr::arrange(dplyr::desc(date))

# ---------------------------------------------------------------------------
# [2/3] Jointure prix + fondamentaux et calcul des ratios par symbole×date
# ---------------------------------------------------------------------------
message("  [2/3] Jointure prix + états et calcul des ratios...")
df <- df_price |>
    dplyr::group_by(symbol) |>
    dplyr::full_join(df_statement, by = c("symbol", "date")) |>
    dplyr::arrange(dplyr::desc(date)) |>
    tidyr::fill(dplyr::all_of(ratio_cols), .direction = "up") |>
    dplyr::ungroup() |>
    dplyr::mutate(
        p_to_s      = close / sales_p_share,
        p_to_ebitda = close / ebitda_p_share,
        pe          = close / eps
    ) |>
    dplyr::filter(!is.na(close))

# Secteur
message("  [2/3] Chargement du mapping secteur...")
sector_map <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "cies_profile_build")) |>
    dplyr::select(symbol, sector) |>
    dplyr::collect()

df <- df |>
    dplyr::left_join(sector_map, by = "symbol")

# ---------------------------------------------------------------------------
# [3/3] Médiane sectorielle quotidienne puis bandes rolling min/max
# ---------------------------------------------------------------------------
message("  [3/3] Médiane sectorielle par date...")
sector_daily <- df |>
    dplyr::filter(!is.na(sector)) |>
    dplyr::group_by(sector, date) |>
    dplyr::summarise(
        n_companies  = dplyr::n(),
        p_to_s_med   = stats::median(p_to_s,      na.rm = TRUE),
        p_to_ebd_med = stats::median(p_to_ebitda, na.rm = TRUE),
        pe_med       = stats::median(pe,          na.rm = TRUE),
        .groups      = "drop"
    ) |>
    dplyr::filter(!is.na(p_to_s_med) | !is.na(p_to_ebd_med) | !is.na(pe_med)) |>
    dplyr::arrange(sector, date)

message("  [3/3] Bandes rolling min/max par secteur...")
safe_min <- function(x) if (all(is.na(x))) NA_real_ else min(x, na.rm = TRUE)
safe_max <- function(x) if (all(is.na(x))) NA_real_ else max(x, na.rm = TRUE)

sector_bands <- sector_daily |>
    dplyr::group_by(sector) |>
    dplyr::filter(dplyr::row_number() > n_days) |>
    dplyr::mutate(
        buy_p_to_s      = slider::slide_dbl(p_to_s_med,   safe_min, .before = n_days),
        sell_p_to_s     = slider::slide_dbl(p_to_s_med,   safe_max, .before = n_days),
        caution_p_to_s  = (buy_p_to_s + sell_p_to_s) / 2,
        buy_p_to_ebd    = slider::slide_dbl(p_to_ebd_med, safe_min, .before = n_days),
        sell_p_to_ebd   = slider::slide_dbl(p_to_ebd_med, safe_max, .before = n_days),
        caution_p_to_ebd = (buy_p_to_ebd + sell_p_to_ebd) / 2,
        buy_pe          = slider::slide_dbl(pe_med,       safe_min, .before = n_days),
        sell_pe         = slider::slide_dbl(pe_med,       safe_max, .before = n_days),
        caution_pe      = (buy_pe + sell_pe) / 2
    ) |>
    dplyr::ungroup()

# ---------------------------------------------------------------------------
# Sortie console + .rds local
# ---------------------------------------------------------------------------
message("  Résultat : ", nrow(sector_bands), " lignes, ",
        length(unique(sector_bands$sector)), " secteur(s).")

latest <- sector_bands |>
    dplyr::group_by(sector) |>
    dplyr::slice_tail(n = 1) |>
    dplyr::ungroup() |>
    dplyr::arrange(dplyr::desc(p_to_ebd_med))

message("\n  Dernières valeurs par secteur (P/EBITDA médian et bandes) :")
for (i in seq_len(nrow(latest))) {
    l <- latest[i, ]
    message(sprintf("    %-25s P/EBITDA %.1f [buy %.1f | sell %.1f]  P/E %.1f  P/S %.1f  (n=%d)",
                    l$sector, l$p_to_ebd_med, l$buy_p_to_ebd, l$sell_p_to_ebd,
                    l$pe_med, l$p_to_s_med, l$n_companies))
}

out_path <- file.path("inst", "script2", "secteur_val_test.rds")
saveRDS(sector_bands, out_path)
message("  .rds écrit dans : ", out_path)
