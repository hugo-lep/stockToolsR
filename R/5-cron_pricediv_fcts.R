#' Mettre à jour la table stockprice
#'
#' @description
#' Met à jour les prix boursiers dans la table `stockprice` pour un vecteur
#' de symboles. Effectue deux appels `tq_get()` distincts :
#'
#' - **Symboles déjà présents** : télécharge depuis la date la plus ancienne
#'   des dernières mises à jour, jusqu'à hier.
#' - **Nouveaux symboles** (absents de la table, ex: post-split) : télécharge
#'   les 12 dernières années, jusqu'à hier.
#'
#' Les doublons éventuels sont éliminés par `anti_join()` avant insertion.
#'
#' @param con Connexion DBI
#' @param symbols Vecteur de tickers à mettre à jour
#'
#' @return Invisiblement TRUE.
#'
#' @importFrom tidyquant tq_get
#' @importFrom dplyr tbl filter group_by summarise collect mutate bind_rows
#'   select anti_join pull
#' @importFrom tibble tibble
#' @importFrom lubridate years
#' @importFrom DBI dbWriteTable
#'
#' @export
#'
#' @examples
#' \dontrun{
#' update_stockprice(con, c("AAPL", "MSFT"))
#' }
update_stockprice <- function(con, symbols) {

  to_date <- Sys.Date()

  # dates max déjà en base pour les symboles demandés
  existing_dates <- dplyr::tbl(con, "stockprice") |>
    dplyr::filter(symbol %in% !!symbols) |>
    dplyr::group_by(symbol) |>
    dplyr::summarise(last_date = max(date, na.rm = TRUE)) |>
    dplyr::collect() |>
    dplyr::mutate(last_date = as.Date(last_date))

  existing_symbols <- existing_dates$symbol
  missing_symbols  <- setdiff(symbols, existing_symbols)

  # --- Appel 1 : symboles déjà présents ---
  if (length(existing_symbols) > 0) {
    from_date <- min(existing_dates$last_date) + 1

    if (from_date <= to_date) {
      message("Mise à jour de ", length(existing_symbols), " ticker(s) depuis le ", from_date, "...")

      df_new <- tidyquant::tq_get(existing_symbols, from = from_date, to = to_date) |>
        dplyr::select(-adjusted) %>%
        filter(date != to_date)

      df_existing_keys <- dplyr::tbl(con, "stockprice") |>
        dplyr::filter(symbol %in% !!existing_symbols, date >= !!from_date) |>
        dplyr::select(symbol, date) |>
        dplyr::collect()

      df_to_add <- dplyr::anti_join(df_new, df_existing_keys, by = c("symbol", "date"))

      if (nrow(df_to_add) > 0) {
        DBI::dbWriteTable(con, "stockprice", df_to_add, append = TRUE)
        message(nrow(df_to_add), " ligne(s) ajoutée(s) pour les tickers existants.")
      } else {
        message("Rien à ajouter pour les tickers existants.")
      }
    } else {
      message("Tickers existants déjà à jour.")
    }
  }

  # --- Appel 2 : nouveaux symboles (post-split ou première fois) ---
  if (length(missing_symbols) > 0) {
    from_date_new <- Sys.Date() - lubridate::years(12)
    message("Import complet pour ", length(missing_symbols), " nouveau(x) ticker(s) : ",
            paste(missing_symbols, collapse = ", "))

    df_new <- tidyquant::tq_get(missing_symbols, from = from_date_new, to = to_date) |>
      dplyr::select(-adjusted) %>%
      filter(date != to_date)

    if (!is.null(df_new) && nrow(df_new) > 0) {
      DBI::dbWriteTable(con, "stockprice", df_new, append = TRUE)
      message(nrow(df_new), " ligne(s) ajoutée(s) pour les nouveaux tickers.")
    }
  }

  invisible(TRUE)
}


#' Mettre à jour la table dividendes
#'
#' @description
#' Met à jour les dividendes dans la table `dividendes` pour un vecteur de symboles.
#' Deux stratégies selon la présence du ticker en base :
#'
#' - **Tickers déjà présents** : un seul appel `fmp_dividends_calendar_get()` depuis
#'   le `max(date)` de la table jusqu'à hier — couvre tous les tickers en une requête.
#' - **Tickers absents** (nouveaux ou post-split) : `fmp_dividends_company_get()`
#'   en boucle avec 12 ans d'historique.
#'
#' Les doublons sont éliminés par `anti_join()` avant insertion.
#'
#' @param con Connexion DBI
#' @param symbols Vecteur de tickers à mettre à jour
#' @param key_fmp_api Clé API Financial Modeling Prep
#'
#' @return Invisiblement TRUE.
#'
#' @importFrom dplyr tbl filter summarise collect mutate pull select anti_join bind_rows
#' @importFrom lubridate years
#' @importFrom purrr map
#' @importFrom DBI dbWriteTable
#'
#' @export
#'
#' @examples
#' \dontrun{
#' update_dividendes(con, c("AAPL", "MSFT"), Sys.getenv("key_fmp_api"))
#' }
update_dividendes <- function(con, symbols, key_fmp_api) {

  to_date <- Sys.Date() - 1

  # Tickers déjà présents vs absents de la table
  existing_symbols <- dplyr::tbl(con, "dividendes") |>
    dplyr::filter(symbol %in% !!symbols) |>
    dplyr::distinct(symbol) |>
    dplyr::collect() |>
    dplyr::pull(symbol)

  missing_symbols <- setdiff(symbols, existing_symbols)

  # Cas 1 : tickers existants → un seul appel calendrier depuis max(date)
  if (length(existing_symbols) > 0) {

    from_date <- dplyr::tbl(con, "dividendes") |>
      dplyr::filter(symbol %in% !!existing_symbols) |>
      dplyr::summarise(max_date = max(date, na.rm = TRUE)) |>
      dplyr::collect() |>
      dplyr::pull(max_date) |>
      as.Date()

    message("Calendrier dividendes depuis le ", from_date, " pour ",
            length(existing_symbols), " ticker(s)...")

    df_cal <- fmp_dividends_calendar_get(from = from_date, to = to_date, key_fmp_api = key_fmp_api)

    if (!is.null(df_cal) && nrow(df_cal) > 0) {
      names(df_cal) <- tolower(names(df_cal))

      df_cal <- df_cal |>
        dplyr::mutate(date = as.Date(date)) |>
        dplyr::filter(!is.na(date), symbol %in% existing_symbols)

      # Anti-join contre toute la table pour ces symboles
      existing_keys <- dplyr::tbl(con, "dividendes") |>
        dplyr::filter(symbol %in% !!existing_symbols) |>
        dplyr::select(symbol, date) |>
        dplyr::collect() |>
        dplyr::mutate(date = as.Date(date))

      df_to_add <- dplyr::anti_join(df_cal, existing_keys, by = c("symbol", "date"))

      if (nrow(df_to_add) > 0) {
        DBI::dbWriteTable(con, "dividendes", df_to_add, append = TRUE)
        message(nrow(df_to_add), " ligne(s) ajoutée(s) pour les tickers existants.")
      } else {
        message("Aucun nouveau dividende pour les tickers existants.")
      }
    }
  }

  # Cas 2 : tickers absents (nouveaux ou post-split) → 12 ans par ticker
  if (length(missing_symbols) > 0) {
    message("Import complet pour ", length(missing_symbols), " nouveau(x) ticker(s) : ",
            paste(missing_symbols, collapse = ", "))

    results <- purrr::map(missing_symbols, \(sym) {
      Sys.sleep(0.2)
      df <- fmp_dividends_company_get(sym, key_fmp_api, limit = 500)
      if (is.null(df) || nrow(df) == 0) return(NULL)
      names(df) <- tolower(names(df))
      df |> dplyr::mutate(date = as.Date(date)) |> dplyr::filter(!is.na(date))
    })

    df_new <- dplyr::bind_rows(results)

    if (nrow(df_new) > 0) {

      # Anti-join pour éviter les doublons (ex: script relancé à mi-chemin)
      existing_keys_new <- dplyr::tbl(con, "dividendes") |>
        dplyr::filter(symbol %in% !!missing_symbols) |>
        dplyr::select(symbol, date) |>
        dplyr::collect() |>
        dplyr::mutate(date = as.Date(date))

      df_to_add <- dplyr::anti_join(df_new, existing_keys_new, by = c("symbol", "date"))

      if (nrow(df_to_add) > 0) {
        DBI::dbWriteTable(con, "dividendes", df_to_add, append = TRUE)
        message(nrow(df_to_add), " ligne(s) ajoutée(s) pour les nouveaux tickers.")
      } else {
        message("Aucun dividende à ajouter pour les nouveaux tickers.")
      }
    } else {
      message("Aucun dividende trouvé pour les nouveaux tickers.")
    }
  }

  invisible(TRUE)
}


#' Récupérer les dividendes d'une compagnie via FMP
#'
#' @description
#' Appelle l'endpoint FMP `/stable/dividends` pour récupérer l'historique
#' des dividendes d'un seul symbole.
#'
#' @param symbol Ticker boursier (ex: "AAPL")
#' @param key_fmp_api Clé API Financial Modeling Prep
#' @param limit Nombre maximal de dividendes à récupérer (défaut : 100)
#'
#' @return Un tibble avec les colonnes retournées par l'API, ou NULL si aucun résultat.
#'
#' @importFrom httr GET content status_code
#' @importFrom tibble as_tibble
#' @importFrom dplyr bind_rows
#'
#' @export
#'
#' @examples
#' \dontrun{
#' fmp_dividends_company_get("AAPL", Sys.getenv("key_fmp_api"))
#' }
fmp_dividends_company_get <- function(symbol, key_fmp_api, limit = 100) {

  url <- paste0(
    "https://financialmodelingprep.com/stable/dividends",
    "?symbol=", symbol,
    "&limit=", limit,
    "&apikey=", key_fmp_api
  )

  resp <- httr::GET(url)

  if (httr::status_code(resp) != 200) {
    warning("Erreur FMP pour ", symbol, " : HTTP ", httr::status_code(resp))
    return(NULL)
  }

  data <- httr::content(resp, as = "parsed", simplifyVector = TRUE)

  if (is.null(data) || length(data) == 0) return(NULL)

  dplyr::bind_rows(data) |> tibble::as_tibble()
}


#' Récupérer le calendrier des dividendes via FMP
#'
#' @description
#' Appelle l'endpoint FMP `/stable/dividends-calendar` pour récupérer les
#' dividendes de toutes les compagnies sur une fenêtre de dates.
#'
#' @param from Date de début (objet Date ou chaîne "YYYY-MM-DD")
#' @param to Date de fin (objet Date ou chaîne "YYYY-MM-DD")
#' @param key_fmp_api Clé API Financial Modeling Prep
#'
#' @return Un tibble avec les colonnes retournées par l'API, ou NULL si aucun résultat.
#'
#' @importFrom httr GET content status_code
#' @importFrom tibble as_tibble
#' @importFrom dplyr bind_rows
#'
#' @export
#'
#' @examples
#' \dontrun{
#' fmp_dividends_calendar_get("2024-01-01", "2024-12-31", Sys.getenv("key_fmp_api"))
#' }
fmp_dividends_calendar_get <- function(from, to, key_fmp_api) {

  url <- paste0(
    "https://financialmodelingprep.com/stable/dividends-calendar",
    "?from=", format(as.Date(from), "%Y-%m-%d"),
    "&to=",   format(as.Date(to),   "%Y-%m-%d"),
    "&apikey=", key_fmp_api
  )

  resp <- httr::GET(url)

  if (httr::status_code(resp) != 200) {
    warning("Erreur FMP calendrier dividendes : HTTP ", httr::status_code(resp))
    return(NULL)
  }

  data <- httr::content(resp, as = "parsed", simplifyVector = TRUE)

  if (is.null(data) || length(data) == 0) return(NULL)

  dplyr::bind_rows(data) |> tibble::as_tibble()
}
