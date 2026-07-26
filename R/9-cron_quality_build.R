#' Reconstruire la table `quality_build`
#'
#' @description
#' Calcule, pour chaque symbol, l'ensemble des ratios de qualité en une seule
#' passe, en joignant cinq sources :
#'
#' - `financial_stmts_build` (dernière période) : ratios de rentabilité,
#'   marges, solidité
#' - `financial_stmts_build` (5 dernières périodes) : moyennes ROA/ROE
#' - `valuation_build` (dernière date) : close, buy ratios
#' - `cagr_stmts_build` : CAGR états financiers
#' - `cies_profile_build` : secteur, industrie
#'
#' Les métriques de dividendes (yield, cagr_div_*) restent dans
#' `dividendes_build` — joindre les deux tables dans le Shiny au besoin.
#'
#' @param con Connexion DBI active (PostgreSQL)
#'
#' @return Invisiblement le tibble écrit dans `quality_build`.
#'
#' @importFrom dplyr tbl collect select mutate arrange group_by slice_head
#'   summarise left_join if_else starts_with rename
#' @importFrom DBI dbGetQuery dbExecute dbWriteTable
#'
#' @export
#'
#' @examples
#' \dontrun{
#' build_quality_build(con)
#' }
build_quality_build <- function(con) {

    # [1/5] Dernière période financière par symbol
    message("  [1/5] Chargement des états financiers (dernière période)...")

    stmts_latest <- DBI::dbGetQuery(con, "
    SELECT DISTINCT ON (symbol)
      symbol, date, period, filingdate,
      is_revenue, is_ebitda, is_ebit, is_netincome,
      is_epsdiluted, is_weightedaverageshsout, is_interestexpense,
      bs_totalassets, bs_totalstockholdersequity,
      bs_totalcurrentassets, bs_totalcurrentliabilities,
      bs_totalliabilities, bs_totaldebt,
      cf_freecashflow,
      m_brut, m_ebitda, m_net
    FROM stocktools.financial_stmts_build
    ORDER BY symbol, date DESC
  ") |>
        dplyr::mutate(
            date           = as.Date(date),
            filingdate     = as.Date(filingdate),
            roa            = is_netincome / bs_totalassets,
            roe            = is_netincome / bs_totalstockholdersequity,
            ratio_courant  = bs_totalcurrentassets / bs_totalcurrentliabilities,
            fcf_rev        = dplyr::if_else(
                !is.na(is_revenue) & is_revenue != 0,
                cf_freecashflow / is_revenue, NA_real_),
            couv_interet   = dplyr::if_else(
                !is.na(is_interestexpense) & is_interestexpense > 0,
                is_ebit / is_interestexpense, NA_real_),
            d_actif        = dplyr::if_else(
                !is.na(bs_totalassets) & bs_totalassets != 0,
                bs_totalliabilities / bs_totalassets, NA_real_),
            pppi           = dplyr::if_else(
                !is.na(bs_totaldebt) & !is.na(bs_totalassets) & bs_totalassets != 0,
                bs_totaldebt / bs_totalassets, NA_real_)
        )

    # [2/5] Moyennes ROA / ROE sur les 5 dernières périodes
    message("  [2/5] Calcul ROA/ROE moyens (5 dernières périodes)...")

    stmts_moy5 <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "financial_stmts_build")) |>
        dplyr::select(symbol, date, is_netincome,
                      bs_totalassets, bs_totalstockholdersequity) |>
        dplyr::collect() |>
        dplyr::mutate(date = as.Date(date)) |>
        dplyr::arrange(symbol, dplyr::desc(date)) |>
        dplyr::group_by(symbol) |>
        dplyr::slice_head(n = 5) |>
        dplyr::summarise(
            roa_moy5 = mean(is_netincome / bs_totalassets,             na.rm = TRUE),
            roe_moy5 = mean(is_netincome / bs_totalstockholdersequity, na.rm = TRUE),
            .groups  = "drop"
        )

    # [3/5] Valorisation, CAGR et profils
    message("  [3/5] Chargement valuation, CAGR et profils...")

    valuation_latest <- DBI::dbGetQuery(con, "
    SELECT DISTINCT ON (symbol)
      symbol, close,
      buy_p_to_s,      sell_p_to_s,
      buy_p_to_ebitda, sell_p_to_ebitda,
      buy_pe,          sell_pe,
      buy_pe_dil,      sell_pe_dil
    FROM stocktools.valuation_build
    ORDER BY symbol, date DESC
  ") |>
        dplyr::mutate(
            r_pts = ifelse(sell_p_to_s      - buy_p_to_s      > 0,
                           (close - buy_p_to_s)      / (sell_p_to_s      - buy_p_to_s),      NA_real_),
            r_ebd = ifelse(sell_p_to_ebitda - buy_p_to_ebitda > 0,
                           (close - buy_p_to_ebitda) / (sell_p_to_ebitda - buy_p_to_ebitda), NA_real_),
            r_pe  = ifelse(sell_pe          - buy_pe          > 0,
                           (close - buy_pe)          / (sell_pe          - buy_pe),          NA_real_),
            r_ped = ifelse(sell_pe_dil      - buy_pe_dil      > 0,
                           (close - buy_pe_dil)      / (sell_pe_dil      - buy_pe_dil),      NA_real_),
            ratio_moyen = rowMeans(cbind(r_pts, r_ebd, r_pe, r_ped), na.rm = TRUE)
        ) |>
        dplyr::select(symbol, close, r_pts, r_ebd, r_pe, r_ped, ratio_moyen)

    # Note : cagr_stmts_build n'est pas chargé ici — ses colonnes restent dans
    # sa propre table (1 ligne/symbol) et sont jointes dans le Shiny au besoin.
    # On charge uniquement cagr_3_is_epsdiluted pour le calcul du PEG.
    cagr_peg <- DBI::dbGetQuery(con, "
    SELECT symbol, cagr_3_is_epsdiluted
    FROM stocktools.cagr_stmts_build
  ")

    profile_data <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "cies_profile_build")) |>
        dplyr::select(symbol, sector, industry) |>
        dplyr::collect()

    # [4/5] Jointure et calcul des ratios de valorisation
    message("  [4/5] Calcul des ratios de valorisation...")

    result <- stmts_latest |>
        dplyr::left_join(stmts_moy5,       by = "symbol") |>
        dplyr::left_join(valuation_latest, by = "symbol") |>
        dplyr::left_join(cagr_peg,         by = "symbol") |>
        dplyr::left_join(profile_data,     by = "symbol") |>
        dplyr::mutate(
            mktcap_m       = dplyr::if_else(
                !is.na(is_weightedaverageshsout) & !is.na(close),
                (is_weightedaverageshsout * close) / 1e6, NA_real_),
            rev_p_share    = dplyr::if_else(
                !is.na(is_weightedaverageshsout) & is_weightedaverageshsout > 0,
                is_revenue / is_weightedaverageshsout, NA_real_),
            ebitda_p_share = dplyr::if_else(
                !is.na(is_weightedaverageshsout) & is_weightedaverageshsout > 0,
                is_ebitda / is_weightedaverageshsout, NA_real_),
            p_to_s_calc    = dplyr::if_else(
                !is.na(rev_p_share)    & rev_p_share    > 0,
                close / rev_p_share,    NA_real_),
            p_to_ebd_calc  = dplyr::if_else(
                !is.na(ebitda_p_share) & ebitda_p_share > 0,
                close / ebitda_p_share, NA_real_),
            pe_calc        = dplyr::if_else(
                !is.na(is_epsdiluted) & is_epsdiluted > 0,
                close / is_epsdiluted,  NA_real_),
            peg_calc       = dplyr::if_else(
                !is.na(pe_calc) & !is.na(cagr_3_is_epsdiluted) & cagr_3_is_epsdiluted > 0,
                pe_calc / (cagr_3_is_epsdiluted * 100), NA_real_),
            last_updated   = Sys.Date()
        ) |>
        dplyr::select(
            symbol, last_updated, sector, industry,
            period, date_stmts = date, filingdate,
            # Rentabilité
            roa, roe, roa_moy5, roe_moy5,
            # Marges
            m_brut, m_ebitda, m_net, fcf_rev,
            # Solidité
            ratio_courant, couv_interet, d_actif, pppi,
            # Marché
            close, mktcap_m,
            # Valorisation
            p_to_s_calc, p_to_ebd_calc, pe_calc, peg_calc,
            # Buy ratios
            r_pts, r_ebd, r_pe, r_ped, ratio_moyen
        )

    # [5/5] Écriture
    message("  [5/5] Écriture dans quality_build (", nrow(result), " lignes)...")
    DBI::dbExecute(con, "TRUNCATE TABLE stocktools.quality_build")
    DBI::dbWriteTable(
        conn   = con,
        name   = DBI::Id(schema = "stocktools", table = "quality_build"),
        value  = result,
        append = TRUE
    )
    message("✔ quality_build : ", nrow(result), " compagnie(s).")

    invisible(result)
}
