# 0-api_fcts.R — Helper DRY : appels API FMP + logging du cron
#
# Fichier prérequis pour toutes les étapes de inst/script2/.
# Contient :
#   - fmp_get()    : un seul point d'appel à l'API FMP (retry, header clé, log)
#   - log_append() : ajoute une ligne au log accumulateur (mémoire)
#   - log_flush()  : sauvegarde le détail (.rds journalier sur S3) + résumé DB
#   - init_log()   : initialise l'accumulateur (appelé en début de 0-plan.R)
#
# La clé API FMP est passée en paramètre (chargée par 0-plan.R via protegR2),
# jamais lue ici — ce fichier reste agnostique sur l'origine de la clé.
#
# Variables d'environnement attendues (posées par s3_connection_HL()) :
#   HL_S3_KEY, HL_S3_SECRET, HL_S3_MAIN_FOLDER, HL_S3_BUCKET,
#   HL_S3_ENDPOINT, HL_S3_REGION

# -----------------------------------------------------------------------------
# État du log — accumulateur en mémoire, interne au package
# -----------------------------------------------------------------------------
# Environnement dédié pour l'état du log. Défini au niveau du package, donc
# non visible dans .GlobalEnv.
log_env <- new.env()

#' Initialiser l'accumulateur de log
#'
#' Vide l'accumulateur `log_env$log_data` (data.frame vide). Appelé en début
#' de `0-plan.R` avant l'exécution des étapes.
#'
#' @return Invisiblement NULL.
#' @export
init_log <- function() {
    log_env$log_data <- data.frame(
        etape   = character(),
        statut  = character(),
        symbol  = character(),
        message = character(),
        stringsAsFactors = FALSE
    )
    invisible(NULL)
}

#' Ajouter une ligne au log en mémoire
#'
#' Ajoute une entrée à l'accumulateur `log_env$log_data`. Les lignes sont
#' ensuite sauvegardées par [log_flush()] (détail S3 + résumé DB).
#'
#' @param etape   Nom de l'étape (ex: "profiles", "splits").
#' @param statut  Statut : `"OK"`, `"WARN"` ou `"ERROR"`.
#' @param symbol  Ticker concerné (ou `NA` si global).
#' @param message Texte du log (succès, avertissement ou erreur).
#'
#' @return Invisiblement `NULL`.
#' @export
log_append <- function(etape, statut, symbol = NA_character_, message = "") {

    if (is.null(log_env$log_data)) init_log()

    log_env$log_data <- rbind(
        log_env$log_data,
        data.frame(
            etape   = as.character(etape),
            statut  = as.character(statut),
            symbol  = as.character(symbol),
            message = as.character(message),
            stringsAsFactors = FALSE
        )
    )
    invisible(NULL)
}

# Vérifie l'existence d'un objet S3 (via s3db::s3exist_HL).
# Retourne TRUE/FALSE. Utilise les paramètres HL_S3_* posés par s3_connection_HL().
.s3_obj_exists <- function(object_name) {
    s3db::s3exist_HL(object = object_name)
}

#' Écrire le résumé en DB + le détail sur S3 (fin de run)
#'
#' Appelé en fin de cron :
#' - le détail (toutes les lignes) est sauvegardé dans un `.rds` journalier
#'   sur S3 (`stockToolsR/logs/YYYY-MM-DD.rds`, main_folder préfixé par s3db) ;
#' - une ligne de résumé est insérée dans `cron_log` (PostgreSQL).
#'
#' La table `cron_log` est créée si elle n'existe pas.
#'
#' @param con       Connexion DBI PostgreSQL.
#' @param run_id    Identifiant du run (ex: entier incrémental). `NULL`
#'   pour générer un `BIGSERIAL` automatique.
#' @param s3_folder Dossier S3 du package (défaut `"stockToolsR/logs"`).
#'
#' @return Invisiblement `TRUE`.
#' @export
log_flush <- function(con, run_id = NULL, s3_folder = "stockToolsR/logs") {

    # Fallback si log_env$started_at n'est pas défini (ex: log_flush appelé isolément)
    started_at <- if (!is.null(log_env$started_at)) log_env$started_at else Sys.time()

    # ---- Compteurs du résumé : calculés sur le run SEUL ----
    # (avant combinaison avec le fichier S3 journalier, qui est un historique
    # cumulé du jour — le résumé DB doit refléter le run actuel uniquement)
    nb_ok   <- sum(log_env$log_data$statut == "OK")
    nb_warn <- sum(log_env$log_data$statut == "WARN")
    nb_err  <- sum(log_env$log_data$statut == "ERROR")

    statut_global <- if (nb_err > 0) "ERROR" else if (nb_warn > 0) "WARN" else "OK"

    message_resume <- paste0(
        "OK=", nb_ok, " WARN=", nb_warn, " ERR=", nb_err
    )

    # ---- Détail sur S3 (fichier journalier, historique cumulé du jour) ----
    jour <- format(Sys.time(), "%Y-%m-%d")
    object_name <- paste0(s3_folder, "/", jour, ".rds")

    # Si le fichier jour existe déjà (run multiple le même jour), on complète.
    # Vérifier l'existence d'abord pour éviter l'erreur S3 NoSuchKey (bruyante)
    if (.s3_obj_exists(object_name)) {
        existing <- s3db::s3readRDS_HL(object = object_name)
        if (!is.null(existing)) {
            log_env$log_data <- rbind(existing, log_env$log_data)
        }
    }

    s3db::s3saveRDS_HL(value = log_env$log_data, object_name = object_name)

    # ---- Résumé en DB (une seule ligne par run) ----

    # Table cron_log créée au besoin (autonomie du helper)
    DBI::dbExecute(con, "
        CREATE TABLE IF NOT EXISTS stocktools.cron_log (
            run_id      BIGSERIAL PRIMARY KEY,
            run_date    DATE        NOT NULL,
            statut      TEXT        NOT NULL,
            nb_ok       INTEGER     NOT NULL DEFAULT 0,
            nb_warn     INTEGER     NOT NULL DEFAULT 0,
            nb_err      INTEGER     NOT NULL DEFAULT 0,
            message     TEXT,
            started_at  TIMESTAMP,
            finished_at TIMESTAMP
        )
    ")

    if (is.null(run_id)) {
        DBI::dbExecute(con, "
            INSERT INTO stocktools.cron_log
              (run_date, started_at, finished_at, statut, nb_ok, nb_warn, nb_err, message)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ", params = list(
            as.Date(started_at),
            started_at,
            Sys.time(),
            statut_global,
            nb_ok, nb_warn, nb_err,
            message_resume
        ))
    } else {
        DBI::dbExecute(con, "
            INSERT INTO stocktools.cron_log
              (run_id, run_date, started_at, finished_at, statut, nb_ok, nb_warn, nb_err, message)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        ", params = list(
            run_id,
            as.Date(started_at),
            started_at,
            Sys.time(),
            statut_global,
            nb_ok, nb_warn, nb_err,
            message_resume
        ))
    }

    message("--- Résumé du run : ", statut_global, " (", message_resume, ") ---")

    # Purge de l'accumulateur après export : les lignes du run sont déjà
    # sauvegardées (S3 + DB), on évite de re-exporter un run précédent.
    log_env$log_data <- NULL

    invisible(TRUE)
}

#' Appel unique à l'API FMP
#'
#' Helper DRY pour toutes les étapes. Centralise :
#'   - la base URL FMP ;
#'   - la clé API par header (pas dans l'URL → pas de fuite dans les logs) ;
#'   - la vérification du statut HTTP 200 ;
#'   - un retry avec backoff (défaut 3 tentatives) ;
#'   - la pause `Sys.sleep(0.2)` (limite FMP : 300 appels/min) ;
#'   - le logging du résultat (via [log_append()]).
#'
#' @param endpoint    Endpoint FMP (ex: `"profile"`, `"splits-calendar"`).
#' @param params      Liste de paramètres query (`symbol`, `limit`, `period`, ...).
#' @param key_fmp_api Clé API FMP (fournie par `0-plan.R` via protegR2).
#' @param max_retries Nombre maximal de tentatives (défaut : 3).
#'
#' @return Le JSON parsé (data frame/liste), ou `NULL` après échec définitif.
#' @export
fmp_get <- function(endpoint, params = list(), key_fmp_api, max_retries = 3) {

    base_url <- "https://financialmodelingprep.com/stable/"

    attempt <- 0
    repeat {
        attempt <- attempt + 1

        res <- tryCatch(
            httr::GET(
                url  = paste0(base_url, endpoint),
                query = params,
                httr::add_headers(
                    "apikey" = key_fmp_api
                )
            ),
            error = function(e) NULL
        )

        if (!is.null(res) && httr::status_code(res) == 200) {
            parsed <- tryCatch(
                jsonlite::fromJSON(rawToChar(res$content)),
                error = function(e) NULL
            )
            if (!is.null(parsed)) {
                return(parsed)
            }
        }

        if (attempt >= max_retries) {
            statut_http <- if (is.null(res)) NA_integer_ else httr::status_code(res)
            log_append(
                etape   = "api",
                statut  = "ERROR",
                message = paste0(
                    "fmp_get(", endpoint, ") échec définitif après ",
                    attempt, " tentative(s), HTTP=", statut_http
                )
            )
            return(NULL)
        }

        Sys.sleep(0.2 * attempt)
    }
}

utils::globalVariables(c("log_env"))