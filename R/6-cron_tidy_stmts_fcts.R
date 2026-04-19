#' Construire et normaliser les états financiers (TTM)
#'
#' @description
#' Construit la table `financial_stmts_build` en combinant les états financiers
#' trimestriels et annuels (income statement, balance sheet, cash flow).
#'
#' - Les données trimestrielles sont annualisées via une somme glissante sur
#'   4 trimestres (`slider::slide_sum(., before = 3, complete = TRUE)`).
#' - Les entrées Q4 trimestrielles sont remplacées par les entrées FY annuelles.
#' - Les colonnes spécifiques sont renommées avec les préfixes `is_`, `bs_`, `cf_`.
#' - Le résultat est écrit dans `financial_stmts_build` (overwrite).
#'
#' @param con Connexion DBI (PostgreSQL)
#' @param keep_cols_gen Colonnes générales à conserver (date, symbol, etc.).
#'   `NA` conserve toutes les colonnes.
#' @param keep_cols_is Colonnes income statement à conserver. `NA` = toutes.
#' @param keep_cols_bs Colonnes balance sheet à conserver. `NA` = toutes.
#' @param keep_cols_cf Colonnes cash flow à conserver. `NA` = toutes.
#'
#' @return Invisiblement le tibble final écrit en base.
#'
#' @importFrom dplyr tbl collect arrange mutate across all_of any_of group_by
#'   ungroup slice anti_join bind_rows left_join select rename_with desc n
#' @importFrom slider slide_sum
#' @importFrom lubridate ymd ymd_hms
#' @importFrom DBI dbWriteTable
#'
#' @export
tidy_stmts <- function(con,
                       keep_cols_gen = NA,
                       keep_cols_is  = NA,
                       keep_cols_bs  = NA,
                       keep_cols_cf  = NA) {

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Sélectionne les colonnes demandées, ou retourne le df complet si NA
  sel_or_all <- function(df, cols_gen, cols_x) {
    if (length(cols_x) == 1 && is.na(cols_x)) return(df)
    df |> dplyr::select(dplyr::all_of(c(cols_gen, cols_x)))
  }

  # Ajoute un préfixe aux colonnes spécifiques à chaque état
  rename_with_prefix <- function(df, cols, prefix) {
    if (length(cols) == 1 && is.na(cols)) return(df)
    df |> dplyr::rename_with(~ paste0(prefix, .x), dplyr::all_of(cols))
  }

  # Income statement


  # Colonnes exclues du rolling sum IS (générales + actions en circulation)
  cols_no_roll_is <- c(
    setdiff(keep_cols_gen, "symbol"),
    "weightedaverageshsout", "weightedaverageshsoutdil"
  )

  # Trimestriels : somme glissante 4 trimestres (TTM), sauf actions en circulation
  is_qts <- dplyr::tbl(con, "qts_income_stmts_orig") |>
    dplyr::collect() |>
    dplyr::arrange(date) |>
    sel_or_all(cols_gen = keep_cols_gen, cols_x = keep_cols_is) |>
    dplyr::mutate(dplyr::across(-dplyr::all_of(keep_cols_gen), as.numeric)) |>
    dplyr::group_by(symbol) |>
    dplyr::mutate(dplyr::across(
      -dplyr::any_of(cols_no_roll_is),
      ~ slider::slide_sum(., before = 3, complete = TRUE)
    )) |>
    dplyr::arrange(symbol, dplyr::desc(date)) |>
    dplyr::slice(1:(dplyr::n() - 3)) |>
    dplyr::ungroup()

  # Annuels : chaque ligne représente déjà un FY complet
  is_fy <- dplyr::tbl(con, "fy_income_stmts_orig") |>
    dplyr::collect() |>
    sel_or_all(cols_gen = keep_cols_gen, cols_x = keep_cols_is) |>
    dplyr::mutate(period2 = "Q4")   # clé fictive pour l'anti_join

  # Remplacer les Q4 trimestriels par les entrées FY annuelles
  income <- is_qts |>
    dplyr::anti_join(is_fy, by = c("symbol", "period" = "period2")) |>
    dplyr::bind_rows(dplyr::select(is_fy, -period2)) |>
    dplyr::mutate(
      date         = as.Date(date),
      filingdate   = as.Date(filingdate),
      accepteddate = as.POSIXct(accepteddate),
      fiscalyear   = as.numeric(fiscalyear)
    ) |>
    rename_with_prefix(cols = keep_cols_is, prefix = "is_")


  # Balance sheet (snapshot — pas de rolling sum)


  bs_fy <- dplyr::tbl(con, "fy_balance_stmts_orig") |> dplyr::collect()

  balance <- dplyr::tbl(con, "qts_balance_stmts_orig") |>
    dplyr::collect() |>
    dplyr::anti_join(bs_fy, by = c("date", "symbol")) |>
    dplyr::bind_rows(bs_fy) |>
    sel_or_all(cols_gen = keep_cols_gen, cols_x = keep_cols_bs) |>
    dplyr::mutate(
      dplyr::across(
        -dplyr::any_of(c("date", "symbol", "reportedcurrency",
                         "period", "filingdate", "accepteddate")),
        as.numeric
      ),
      date       = lubridate::ymd(date),
      filingdate = lubridate::ymd(filingdate)
    ) |>
    dplyr::select(-dplyr::any_of(setdiff(keep_cols_gen, c("date", "symbol")))) |>
    dplyr::arrange(symbol, dplyr::desc(date)) |>
    rename_with_prefix(cols = keep_cols_bs, prefix = "bs_")


  # Cash flow


  cf_fy <- dplyr::tbl(con, "fy_cf_stmts_orig") |>
    dplyr::collect() |>
    sel_or_all(cols_gen = keep_cols_gen, cols_x = keep_cols_cf) |>
    dplyr::mutate(dplyr::across(-dplyr::all_of(keep_cols_gen), as.double))

  cf_qts <- dplyr::tbl(con, "qts_cf_stmts_orig") |>
    dplyr::collect() |>
    dplyr::arrange(date) |>
    sel_or_all(cols_gen = keep_cols_gen, cols_x = keep_cols_cf) |>
    dplyr::mutate(dplyr::across(
      -dplyr::all_of(keep_cols_gen),
      as.double
    )) |>
    dplyr::group_by(symbol) |>
    dplyr::mutate(dplyr::across(
      -dplyr::all_of(setdiff(keep_cols_gen, "symbol")),
      ~ slider::slide_sum(., before = 3, complete = TRUE)
    )) |>
    dplyr::arrange(symbol, dplyr::desc(date)) |>
    dplyr::slice(1:(dplyr::n() - 3)) |>
    dplyr::ungroup()

  cashflow <- cf_qts |>
    dplyr::anti_join(cf_fy, by = c("date", "symbol")) |>
    dplyr::bind_rows(cf_fy) |>
    dplyr::mutate(
      date       = lubridate::ymd(date),
      filingdate = lubridate::ymd(filingdate)
    ) |>
    dplyr::select(-dplyr::any_of(setdiff(keep_cols_gen, c("date", "symbol")))) |>
    rename_with_prefix(cols = keep_cols_cf, prefix = "cf_")

  # ---------------------------------------------------------------------------
  # Jointure finale et écriture
  # ---------------------------------------------------------------------------

  final <- income |>
    dplyr::left_join(balance,  by = c("date", "symbol")) |>
    dplyr::left_join(cashflow, by = c("date", "symbol")) |>
    dplyr::arrange(symbol, dplyr::desc(date)) |>
    dplyr::distinct(symbol, date, .keep_all = TRUE) |>
    dplyr::mutate(
      caf    = is_netincome + is_depreciationandamortization + cf_stockbasedcompensation,
      # Normaliser Q4 → FY (les deux sont équivalents : rapport annuel)
      period = dplyr::if_else(period == "Q4", "FY", period)
    )

  # Pour chaque symbol, détecter la period de la ligne la plus récente
  period_ref <- final |>
    dplyr::group_by(symbol) |>
    dplyr::slice_max(date, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(symbol, period_ref = period)

  # Ne conserver que les lignes dont la period correspond à la référence
  final <- final |>
    dplyr::left_join(period_ref, by = "symbol") |>
    dplyr::filter(period == period_ref) |>
    dplyr::select(-period_ref)

  final <- final |>
    mutate(m_brut = is_grossprofit / is_revenue,
           m_ebitda = is_ebitda / is_revenue,
           m_net = is_netincome / is_revenue)

  DBI::dbWriteTable(con, "financial_stmts_build", final, overwrite = TRUE)
  message(nrow(final), " ligne(s) écrite(s) dans financial_stmts_build.")

  invisible(final)
}
