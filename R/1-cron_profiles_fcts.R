#' Get company profile from Financial Modeling Prep API
#'
#' @description
#' Récupère le profil d’une compagnie (description, secteur, CEO, site web, etc.)
#' depuis l’API Financial Modeling Prep. Retourne `NULL` si l’appel échoue.
#'
#' @param symbol Ticker boursier (ex: `"AAPL"`)
#' @param key_fmp_api Clé API Financial Modeling Prep
#'
#' @return Un data.frame (ou liste) issu du JSON retourné par l’API,
#' ou `NULL` en cas d’erreur.
#'
#' @importFrom httr GET add_headers status_code
#' @importFrom jsonlite fromJSON
#'
#' @export
fmp_profile_get <- function(symbol, key_fmp_api) {

  headers <- c(`Upgrade-Insecure-Requests` = "1")
  params  <- list(datatype = "json")

  res <- tryCatch(
    httr::GET(
      url = paste0(
        "https://financialmodelingprep.com/stable/profile?",
        "symbol=", symbol,
        "&apikey=", key_fmp_api
      ),
      httr::add_headers(.headers = headers),
      query = params
    ),
    error = function(e) NULL
  )

  if (is.null(res) || httr::status_code(res) != 200) {
    return(NULL)
  }

  tryCatch(
    jsonlite::fromJSON(rawToChar(res$content)),
    error = function(e) NULL
  )
}

#' Store company profile in database (Financial Modeling Prep)
#'
#' @description
#' Récupère le profil d’une compagnie via l’API Financial Modeling Prep
#' et l’enregistre dans la table `cie_profile_orig`.
#'
#' La table doit déjà exister et contenir au moins une ligne.
#' Si le symbole existe déjà et que `force = FALSE`, aucun appel API n’est fait.
#' Si `force = TRUE`, le profil est re-téléchargé et remplace la ligne existante.
#'
#' @param con Connexion DBI (SQLite)
#' @param symbol Ticker boursier (ex: `"AAPL"`)
#' @param key_fmp_api Clé API Financial Modeling Prep
#' @param force Logique. Forcer la mise à jour même si le symbole existe déjà.
#'
#' @return Le `data.frame` retourné par `fmp_get_profile`, ou `NULL`
#' si aucun appel API n’a été effectué.
#'
#' @importFrom DBI dbExistsTable dbWriteTable dbExecute
#' @importFrom dplyr tbl filter summarise n collect pull
#'
#' @export
#'
#' @examples
#' \dontrun{
#' con <- DBI::dbConnect(RSQLite::SQLite(), "ma_db.sqlite")
#'
#' fmp_profile_add_to_db(
#'   con,
#'   symbol = "AAPL",
#'   key_fmp_api = Sys.getenv("key_fmp_api")
#' )
#'
#' fmp_profile_add_to_db(
#'   con,
#'   symbol = "AAPL",
#'   key_fmp_api = Sys.getenv("key_fmp_api"),
#'   force = TRUE
#' )
#' }
fmp_profile_add_to_db <- function(symbol, con, key_fmp_api, force = FALSE) {

  if (!DBI::dbExistsTable(con, DBI::Id(schema = "stocktools", table = "cies_profile_orig"))) {
    stop("La table 'cies_profile_orig' n'existe pas.")
  }

  cies_tbl <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "cies_profile_orig"))

  exists <- cies_tbl %>%
    dplyr::filter(symbol == !!symbol) %>%
    dplyr::summarise(n = dplyr::n()) %>%
    dplyr::collect() %>%
    dplyr::pull(n) > 0

  if (exists && !force) {
    message(symbol, " déjà dans la table")
    return(invisible(NULL))
  }

  profile <- fmp_profile_get(symbol = symbol,
                             key_fmp_api = key_fmp_api)

  if (is.null(profile)) return(NULL)
  names(profile) <- tolower(names(profile))

  if (!"symbol" %in% names(profile)) {
    profile$symbol <- symbol
  }

  # Ajouter la date de récupération
  profile$last_updated <- Sys.Date()

  if (exists) {
    DBI::dbExecute(
      con,
      "DELETE FROM stocktools.cies_profile_orig WHERE symbol = $1",
      params = list(symbol)
    )
  }

  DBI::dbWriteTable(
    con,
    DBI::Id(schema = "stocktools", table = "cies_profile_orig"),
    profile,
    append = TRUE
  )
  message(symbol, " ajouté")

  invisible(profile)
}

utils::globalVariables(c(
  "symbol", "companyName", "currency", "cik", "cusip", "exchange", "industry", "website", "description", "sector", "image"
))
#' Build simplified company profile table
#'
#' @description
#' Prend la table `cies_profile_orig` et crée/écrase `cies_profile_build`
#' avec seulement les colonnes utiles.
#'
#' @param con Connexion DBI
#'
#' @importFrom dplyr select collect
#' @importFrom magrittr %>%
#'
#'
#'
#' @export
cies_profile_build <- function(con) {

  if (!DBI::dbExistsTable(con, DBI::Id(schema = "stocktools", table = "cies_profile_orig"))) {
    stop("La table 'cies_profile_orig' n'existe pas.")
  }

  data <- tbl(con, dbplyr::in_schema("stocktools", "cies_profile_orig")) %>%
    select(symbol, companyname, currency, cik, cusip, exchange, industry,
           website, description, sector, image, last_updated) %>%
    collect()

  DBI::dbWriteTable(
    con,
    DBI::Id(schema = "stocktools", table = "cies_profile_build"),
    data,
    overwrite = TRUE
  )

  invisible(data)
}
#' Get symbols from FMP company screener
#'
#' @description
#' Récupère une liste de tickers filtrés (exchange, market cap, etc.)
#' depuis l’API Financial Modeling Prep.
#'
#' @param key_fmp_api Clé API Financial Modeling Prep
#' @param exchange Exchange (ex: "NASDAQ", "NYSE", "AMEX")
#' @param country Pays (ex: "US")
#' @param limit Nombre max de résultats (max recommandé: 10000)
#'
#' @return Un data.frame ou NULL
#'
#' @export
fmp_company_screener <- function(
    key_fmp_api,
    exchange = "NASDAQ",
    country = "US",
    limit = 10000
) {

  res <- tryCatch(
    httr::GET(
      url = "https://financialmodelingprep.com/stable/company-screener",
      query = list(
        exchange = exchange,
        country = country,
        isEtf = FALSE,
        isFund = FALSE,
        isActivelyTrading = TRUE,
        limit = limit,
        apikey = key_fmp_api
      )
    ),
    error = function(e) NULL
  )

  if (is.null(res) || httr::status_code(res) != 200) {
    return(NULL)
  }

  tryCatch(
    jsonlite::fromJSON(rawToChar(res$content)),
    error = function(e) NULL
  )
}
