# =============================================================================
# utils_globals.R — Suppressions R CMD check
#
# - utils::globalVariables() : noms de colonnes utilisés dans les verbes dplyr
#   (pas de vraies variables globales — c'est le mécanisme standard tidyverse)
# - @importFrom : fonctions de packages déjà en Imports dans DESCRIPTION
# =============================================================================

#' @importFrom stats na.omit setNames median
#' @importFrom rlang .data :=
#' @importFrom tidyr drop_na
NULL

utils::globalVariables(c(

  # ── États financiers (income statement) ──────────────────────────────────────
  "is_revenue", "is_grossprofit", "is_ebitda", "is_netincome",
  "is_depreciationandamortization", "is_eps", "is_epsdiluted",
  "is_weightedaverageshsout",

  # ── Balance sheet ─────────────────────────────────────────────────────────────
  "bs_totalcurrentassets", "bs_totalcurrentliabilities",

  # ── Cash flow ─────────────────────────────────────────────────────────────────
  "cf_freecashflow", "cf_stockbasedcompensation",

  # ── Colonnes générales états financiers ───────────────────────────────────────
  "period", "period2", "filingdate", "accepteddate", "fiscalyear",

  # ── Ratios de qualité calculés ────────────────────────────────────────────────
  "marge_brute", "marge_ebitda", "marge_nette", "fcf_rev", "ratio_courant",

  # ── Valorisation — métriques brutes ──────────────────────────────────────────
  "sales_p_share", "ebitda_p_share", "eps", "eps_dil",
  "p_to_s", "p_to_ebitda", "pe", "pe_dil",

  # ── Valorisation — bornes buy / caution / sell ───────────────────────────────
  "min_p_to_s",    "max_p_to_s",    "buy_p_to_s",    "sell_p_to_s",    "caution_p_to_s",
  "min_p_to_ebitda","max_p_to_ebitda","buy_p_to_ebitda","sell_p_to_ebitda","caution_p_to_ebitda",
  "min_pe",        "max_pe",        "buy_pe",        "sell_pe",        "caution_pe",
  "min_pe_dil",    "max_pe_dil",    "buy_pe_dil",    "sell_pe_dil",    "caution_pe_dil",

  # ── Valorisation — colonnes graphique (après rename via all_of) ───────────────
  "buy", "caution", "sell",

  # ── Ratios buy→sell (mod_finance_server) ─────────────────────────────────────
  "r_pts", "r_ebd", "r_pe", "r_ped", "ratio_moyen",

  # ── Profil compagnies ─────────────────────────────────────────────────────────
  "companyname", "last_updated",

  # ── CAGR ─────────────────────────────────────────────────────────────────────
  "cagr_3_is_revenue", "cagr_3_is_ebitda", "cagr_3_is_epsdiluted",

  # ── Prix / dividendes ─────────────────────────────────────────────────────────
  "adjusted", "last_date", "max_date", "first_date",

  # ── Splits ───────────────────────────────────────────────────────────────────
  "numerator", "denominator", "split_date", "split_ratio",

  # ── Calendrier publications ───────────────────────────────────────────────────
  "reportDate", "reportDate_mod", "status"
))
