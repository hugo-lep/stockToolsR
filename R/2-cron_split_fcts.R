#' Get stock splits calendar from Financial Modeling Prep API (with date range)
#'
#' @description
#' Récupère le calendrier des splits boursiers pour tous les tickers depuis l’API Financial Modeling Prep,
#' en filtrant sur une plage de dates.
#'
#' @param fmp_api_key Clé API Financial Modeling Prep
#' @param from Date de début au format "YYYY-MM-DD"
#' @param to   Date de fin au format "YYYY-MM-DD"
#'
#' @return Un data.frame issu du JSON retourné par l’API, ou `NULL` si l’appel échoue.
#'
#' @importFrom httr GET add_headers status_code
#' @importFrom jsonlite fromJSON
#'
#' @export
fmp_splits_calendar_get <- function(fmp_api_key, from = NULL, to = NULL) {

  headers <- c(`Upgrade-Insecure-Requests` = "1")
  params <- list(
    datatype = "json",
    from = from,
    to = to
  )

  # Supprime les NULL pour ne pas envoyer de paramètre vide
  params <- params[!sapply(params, is.null)]

  url <- paste0(
    "https://financialmodelingprep.com/stable/splits-calendar?",
    "apikey=", fmp_api_key
  )

  res <- tryCatch(
    httr::GET(url, httr::add_headers(.headers = headers), query = params),
    error = function(e) NULL
  )

  if (is.null(res) || httr::status_code(res) != 200) return(NULL)

  tryCatch(
    jsonlite::fromJSON(rawToChar(res$content)),
    error = function(e) NULL
  )
}

#' Détecter et insérer les splits des tickers S&P 500
#'
#' @description
#' Appelle l’API Financial Modeling Prep pour récupérer les splits sur une fenêtre de ±10 jours autour de la date courante,
#' filtre uniquement les tickers du S&P 500, calcule le ratio de split, et les insère dans la table `split_log`
#' avec le statut `"pending"`. Les doublons `(symbol, split_date)` sont ignorés grâce à `ON CONFLICT DO NOTHING`.
#'
#' @param tickers Character vector des tickers S&P 500 à surveiller
#' @param con Connexion à la database
#' @param fmp_api_key Clé API Financial Modeling Prep
#'
#' @return Invisiblement `NULL`. La fonction produit des messages sur la console indiquant les splits détectés et insérés.
#' @export
detect_and_insert_splits <- function(tickers,con, fmp_api_key) {

  today <- Sys.Date()
  from  <- format(today - 10, "%Y-%m-%d")
  to    <- format(today + 10, "%Y-%m-%d")

  message(glue::glue("🔍 Détection splits du {from} au {to}..."))

  # --- Appel API ---
  splits_raw <- fmp_splits_calendar_get(fmp_api_key, from = from, to = to)

  if (is.null(splits_raw) || nrow(splits_raw) == 0) {
    message("⚠ Aucun split retourné par FMP.")
    return(invisible(NULL))
  }

  # --- Filtrer sur S&P 500 + calculer ratio ---
  splits <- splits_raw %>%
    filter(symbol %in% tickers) %>%
    mutate(
      split_ratio = numerator / denominator,
      split_date  = as.Date(date)
    ) %>%
    select(symbol, split_date, split_ratio)

  if (nrow(splits) == 0) {
    message("✔ Aucun split détecté pour les tickers S&P 500.")
    return(invisible(NULL))
  }

  message(glue::glue("📋 {nrow(splits)} split(s) détecté(s) pour le S&P 500."))

  # --- Insérer en pending (ON CONFLICT DO NOTHING) ---

  purrr::pwalk(splits, function(symbol, split_date, split_ratio) {
    dbExecute(con, "
    INSERT INTO split_log (symbol, split_date, split_ratio, status, detected_date)
    VALUES ($1, $2, $3, 'pending', CURRENT_DATE)
    ON CONFLICT (symbol, split_date) DO NOTHING;
  ", params = list(symbol, as.character(split_date), split_ratio))
    message(glue::glue("  ✔ {symbol} | {split_date} | ratio {split_ratio}"))
  })

  message("✔ Détection splits terminée.")
}
#' Récupérer les splits "pending" à traiter
#'
#' @description
#' Retourne les splits dont le statut est `"pending"` et dont la date de split
#' est inférieure ou égale à aujourd'hui + `horizon_days`.
#'
#' Utiliser `horizon_days = -1` (défaut) pour ne traiter que les splits survenus
#' **avant aujourd'hui**, afin de laisser le temps aux fournisseurs de données
#' (Yahoo Finance, FMP) d'ajuster leurs prix historiques avant le nettoyage.
#'
#' @param con Objet `DBIConnection`
#' @param horizon_days Décalage en jours par rapport à aujourd'hui (par défaut -1)
#'
#' @return `data.frame` contenant les splits pending triés par `split_date` croissant.
#'
#' @importFrom DBI dbReadTable
#' @importFrom dplyr filter arrange
#'
#' @export
get_pending_splits <- function(con, horizon_days = -1) {
  date_limite <- Sys.Date() + horizon_days
  DBI::dbReadTable(con, "split_log") |>
    dplyr::filter(
      status == "pending",
      as.Date(split_date) <= date_limite
    ) |>
    dplyr::arrange(split_date)
}
#' Confirmer un split après nettoyage réussi
#'
#' @description
#' Met à jour la ligne correspondante dans `split_log` pour indiquer que le
#' nettoyage des données a été effectué avec succès. Les champs `status`,
#' `confirmed_date` et `rewrite_date` sont mis à jour à la date du jour.
#'
#' @param con Objet `DBIConnection`
#' @param symbol Ticker de l'action (ex: `"AAPL"`)
#' @param split_date Date du split (`Date` ou `character` au format `"YYYY-MM-DD"`)
#' @param notes Optionnel : texte libre pour commentaires (ex: `"Nettoyage effectué via cron"`)
#'
#' @return Invisiblement NULL.
#'
#' @importFrom DBI dbExecute
#'
#' @export
confirm_split <- function(con, symbol, split_date, notes = NULL) {
  DBI::dbExecute(con, "
    UPDATE split_log
    SET status         = 'confirmed',
        confirmed_date = CURRENT_DATE,
        rewrite_date   = CURRENT_DATE,
        notes          = $3
    WHERE symbol     = $1
      AND split_date = $2;
  ", params = list(symbol, as.character(split_date), notes))
  message("Split confirmé : ", symbol, " | ", split_date)
  invisible(NULL)
}
