#' Get a financial statement from Financial Modeling Prep API
#'
#' @description
#' Récupère un état financier (income, balance-sheet ou cash-flow) depuis l'API
#' Financial Modeling Prep. Retourne `NULL` si l'appel échoue ou si le statut
#' HTTP n'est pas 200.
#'
#' @param statement Type de rapport (`"income"`, `"balance-sheet"`, `"cash-flow"`)
#' @param symbol Ticker boursier (ex: `"AAPL"`)
#' @param limit Nombre de rapports à retourner
#' @param period Période (`"FY"`, `"Q1"`, `"Q2"`, `"Q3"`, `"Q4"`)
#' @param key_fmp_api Clé API Financial Modeling Prep
#'
#' @return Un data.frame issu du JSON retourné par l'API, ou `NULL` en cas d'erreur.
#'
#' @importFrom httr GET add_headers status_code
#' @importFrom jsonlite fromJSON
#'
#' @export
#'
#' @examples
#' \dontrun{
#' fmp_get_statement(
#'   statement   = "income",
#'   symbol      = "AAPL",
#'   limit       = 12,
#'   period      = "Q1",
#'   key_fmp_api = Sys.getenv("key_fmp_api")
#' )
#' }
fmp_get_statement <- function(statement, symbol, limit, period, key_fmp_api) {

  headers <- c(`Upgrade-Insecure-Requests` = "1")

  res <- tryCatch(
    httr::GET(
      url = paste0(
        "https://financialmodelingprep.com/stable/",
        statement, "-statement?symbol=", symbol,
        "&limit=", limit,
        "&period=", period,
        "&apikey=", key_fmp_api
      ),
      httr::add_headers(.headers = headers),
      query = list(datatype = "json")
    ),
    error = function(e) NULL
  )

  if (is.null(res) || httr::status_code(res) != 200) return(NULL)

  tryCatch(
    jsonlite::fromJSON(rawToChar(res$content)),
    error = function(e) NULL
  )
}


#' Get all financial statements for a company
#'
#' @description
#' Récupère l'ensemble des états financiers d'une compagnie via l'API
#' Financial Modeling Prep :
#' - États trimestriels (Q1 à Q4) : income statement, balance sheet, cash flow
#' - États annuels (FY) : idem
#'
#' @param symbol Ticker boursier (ex: `"AAPL"`)
#' @param key_fmp_api Clé API Financial Modeling Prep
#' @param limit Nombre de rapports à retourner par période.
#'   Utiliser `12` pour un historique complet, `4` pour une mise à jour récente.
#'
#' @return Une liste nommée :
#' \itemize{
#'   \item `income`   : liste de 4 éléments (Q1 à Q4)
#'   \item `balance`  : liste de 4 éléments (Q1 à Q4)
#'   \item `cashflow` : liste de 4 éléments (Q1 à Q4)
#'   \item `annual`   : liste de 3 éléments (income FY, balance FY, cashflow FY)
#' }
#'
#' @importFrom purrr map
#'
#' @export
#'
#' @examples
#' \dontrun{
#' stmts <- fmp_get_stmts_new_cie("AAPL", Sys.getenv("key_fmp_api"), limit = 12)
#' str(stmts)
#' }
fmp_get_stmts_new_cie <- function(symbol, key_fmp_api, limit) {

  quarters   <- c("Q1", "Q2", "Q3", "Q4")
  statements <- c("income", "balance-sheet", "cash-flow")

  get_quarterly <- function(type) {
    purrr::map(
      quarters,
      function(q) fmp_get_statement(
        statement   = type,
        symbol      = symbol,
        limit       = limit,
        period      = q,
        key_fmp_api = key_fmp_api
      )
    )
  }

  list(
    income   = get_quarterly("income"),
    balance  = get_quarterly("balance-sheet"),
    cashflow = get_quarterly("cash-flow"),
    annual   = purrr::map(
      statements,
      function(s) fmp_get_statement(
        statement   = s,
        symbol      = symbol,
        limit       = limit,
        period      = "FY",
        key_fmp_api = key_fmp_api
      )
    )
  )
}


#' Update all financial statements for a company into the database
#'
#' @description
#' Met à jour toutes les tables d'états financiers (trimestriels et annuels)
#' à partir d'un objet retourné par `fmp_get_stmts_new_cie()`.
#'
#' @param df Liste retournée par `fmp_get_stmts_new_cie()`
#' @param con Connexion DBI
#' @param replace Logique. Si `TRUE`, les lignes existantes sont remplacées.
#'   Si `FALSE` (défaut), seules les nouvelles lignes sont ajoutées.
#'
#' @return Invisiblement NULL.
#'
#' @importFrom dplyr bind_rows
#'
#' @export
#'
#' @examples
#' \dontrun{
#' df <- fmp_get_stmts_new_cie("AAPL", Sys.getenv("key_fmp_api"), limit = 12)
#' fmp_original_stmts_update(df, con)
#' }
fmp_original_stmts_update <- function(df, con, replace = FALSE) {

  update_statement_table(con, df = dplyr::bind_rows(df$income),   "qts_income_stmts_orig",  c("date", "symbol"), replace)
  update_statement_table(con, dplyr::bind_rows(df$balance),  "qts_balance_stmts_orig", c("date", "symbol"), replace)
  update_statement_table(con, dplyr::bind_rows(df$cashflow), "qts_cf_stmts_orig",      c("date", "symbol"), replace)
  update_statement_table(con, df$annual[[1]],                "fy_income_stmts_orig",   c("date", "symbol"), replace)
  update_statement_table(con, df$annual[[2]],                "fy_balance_stmts_orig",  c("date", "symbol"), replace)
  update_statement_table(con, df$annual[[3]],                "fy_cf_stmts_orig",       c("date", "symbol"), replace)

  invisible(NULL)
}


#' Upsert d'une table d'états financiers dans PostgreSQL
#'
#' @description
#' Met à jour une table PostgreSQL à partir d'un data.frame.
#' Les lignes sont comparées via les colonnes de référence (`cols_ref`).
#'
#' - Si `replace = TRUE` : les lignes existantes correspondant au df sont
#'   supprimées puis toutes les lignes du df sont insérées.
#' - Si `replace = FALSE` : seules les nouvelles lignes (absentes de la table)
#'   sont ajoutées.
#'
#' @param con Connexion DBI
#' @param df data.frame contenant les données à synchroniser
#' @param table_name Nom de la table PostgreSQL
#' @param cols_ref Vecteur de colonnes servant de clé logique (ex: `c("date", "symbol")`)
#' @param replace Logique. Si `TRUE`, remplace les lignes existantes. Défaut : `FALSE`.
#'
#' @return Invisiblement, le data.frame effectivement inséré, ou `NULL` si rien à insérer.
#'
#' @importFrom DBI dbExistsTable dbWriteTable dbExecute
#' @importFrom dplyr tbl select distinct collect anti_join semi_join pull
#' @importFrom tidyselect all_of
#'
#' @export
update_statement_table <- function(con, df, table_name, cols_ref, replace = FALSE) {

  # vérifications en premier, avant toute transformation
  if (is.null(df) || nrow(df) == 0) {
    message(table_name, " : aucune donnée à insérer.")
    return(invisible(NULL))
  }

  if (!DBI::dbExistsTable(con, table_name)) {
    stop("La table '", table_name, "' n'existe pas.")
  }

  # conversion des dates et noms de colonnes en minuscules (PostgreSQL)
  df <- df %>%
    mutate(date = ymd(date))
  names(df) <- tolower(names(df))

  existing_keys <- dplyr::tbl(con, table_name) |>
    dplyr::select(dplyr::all_of(cols_ref)) |>
    dplyr::distinct() |>
    dplyr::collect()

  if (replace) {
    keys_to_delete <- df |>
      dplyr::select(dplyr::all_of(cols_ref)) |>
      dplyr::distinct() |>
      dplyr::semi_join(existing_keys, by = cols_ref)

    if (nrow(keys_to_delete) > 0) {
      # suppression ligne par ligne pour éviter la concaténation SQL
      for (i in seq_len(nrow(keys_to_delete))) {
        DBI::dbExecute(
          con,
          paste0(
            "DELETE FROM ", table_name,
            " WHERE symbol = $1 AND date = $2"
          ),
          params = list(keys_to_delete$symbol[i], as.character(keys_to_delete$date[i]))
        )
      }
    }

    df_to_insert <- df

  } else {
    df_to_insert <- df |>
      dplyr::anti_join(existing_keys, by = cols_ref)

    if (nrow(df_to_insert) == 0) {
      message(table_name, " : rien à ajouter.")
      return(invisible(NULL))
    }
  }

  DBI::dbWriteTable(con, table_name, df_to_insert, append = TRUE)
  message(table_name, " : ", nrow(df_to_insert), " ligne(s) insérée(s).")
  invisible(df_to_insert)
}


#' Vérifier la présence des états financiers autour d'une date attendue
#'
#' @description
#' Pour un symbole donné, vérifie si un enregistrement existe dans chacune
#' des 3 tables d'états financiers trimestriels, dans une fenêtre de
#' ±`tolerance_days` jours autour de la date de publication attendue.
#'
#' Utilisé après l'import pour confirmer que les données ont bien été reçues.
#'
#' @param con Connexion DBI
#' @param symbol Ticker boursier (ex: `"AAPL"`)
#' @param expected_date Date attendue de publication (`Date` ou `character`)
#' @param tolerance_days Nombre de jours de tolérance de part et d'autre (défaut : 7)
#'
#' @return Liste nommée avec trois éléments : `inc_status`, `bs_status`, `cf_status`.
#'   Chaque valeur est `"complete"` ou `"incomplete"`.
#'
#' @importFrom dplyr tbl filter collect
#' @importFrom lubridate ymd
#'
#' @export
check_filing_exists <- function(con, symbol, expected_date, tolerance_days = 7) {

  date_from <- as.character(as.Date(expected_date) - tolerance_days)
  date_to   <- as.character(as.Date(expected_date) + tolerance_days)

  check_table <- function(table_name) {
    dplyr::tbl(con, table_name) |>
      dplyr::filter(
        symbol     == !!symbol,
        filingdate >= !!date_from,
        filingdate <= !!date_to
      ) |>
      dplyr::collect() |>
      nrow() > 0
  }

  list(
    inc_status = ifelse(check_table("qts_income_stmts_orig"),  "complete", "incomplete"),
    bs_status  = ifelse(check_table("qts_balance_stmts_orig"), "complete", "incomplete"),
    cf_status  = ifelse(check_table("qts_cf_stmts_orig"),      "complete", "incomplete")
  )
}
