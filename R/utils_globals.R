# utils_globals.R — Suppressions R CMD check
#
# - utils::globalVariables() : noms de colonnes utilisés dans les verbes dplyr
#   (pas de vraies variables globales — c'est le mécanisme standard tidyverse)
# - @importFrom : fonctions de packages déjà en Imports dans DESCRIPTION

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
  "companyname", "last_updated", "sector", "industry",

  # ── CAGR ─────────────────────────────────────────────────────────────────────
  "cagr_3_is_revenue", "cagr_3_is_ebitda", "cagr_3_is_epsdiluted",
  "cagr_1_is_revenue", "cagr_1_is_ebitda", "cagr_1_is_epsdiluted",
  "cagr_1_cf_freecashflow",
  "cagr_3_cf_freecashflow", "cagr_5_cf_freecashflow", "cagr_10_cf_freecashflow",

  # ── États financiers — colonnes supplémentaires (mod_finance2) ───────────────
  "is_ebit", "is_interestexpense",
  "bs_totalassets", "bs_totalstockholdersequity", "bs_totalliabilities",
  "m_brut", "m_ebitda", "m_net",
  "couv_interet", "d_actif",
  "roa", "roe",

  # ── Valorisation — ratios calculés (mod_finance2) ────────────────────────────
  "rev_p_share", "ebitda_p_share_v",
  "p_to_s_calc", "p_to_ebd_calc", "pe_calc", "peg_calc",

  # ── Marché — métriques (mod_finance2) ────────────────────────────────────────
  "mktcap_m",

  # ── Dividendes ────────────────────────────────────────────────────────────────
  "adjdividend", "div_annuel", "div_yield",
  "frequency", "close_ref",
  "div_ttm", "div_forward", "croissance_reguliere",
  "yield",
  "cagr_div_1a", "cagr_div_3a", "cagr_div_5a", "cagr_div_10a",
  "fcf_payout", "fcf_coverage",
  "has_special", "has_irregular", "last_special_date", "last_irregular_date",
  "last_div_date",

  # ── Prix / dividendes ─────────────────────────────────────────────────────────
  "adjusted", "last_date", "max_date", "first_date",

  # ── Splits ───────────────────────────────────────────────────────────────────
  "numerator", "denominator", "split_date", "split_ratio",

  # ── Quality build ─────────────────────────────────────────────────────────────
  "roa_moy5", "roe_moy5",
  "date_stmts", "ebitda_p_share",
  "pppi",

  # ── Balance sheet — dette ─────────────────────────────────────────────────────
  "bs_totaldebt", "bs_shorttermdebt", "bs_longtermdebt",

  # ── Prix CAGR (cagr_price_build) — mod_finance3 ───────────────────────────────
  "cagr_1y", "cagr_3y", "cagr_5y", "cagr_10y",

  # ── CAGR états financiers supplémentaires — mod_finance3 ──────────────────────
  "cagr_5_is_revenue",     "cagr_10_is_revenue",
  "cagr_5_is_ebitda",      "cagr_10_is_ebitda",
  "cagr_5_is_epsdiluted",  "cagr_10_is_epsdiluted",

  # ── Calendrier publications ───────────────────────────────────────────────────
  "reportDate", "reportDate_mod", "status"
))
