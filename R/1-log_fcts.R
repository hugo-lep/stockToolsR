# 1-log_fcts.R — Consultation des logs du cron (résumé DB + détail S3)
#
# Fonctions de lecture réutilisables par le module Shiny (dans le projet
# séparé) :
#   - log_get_summary() : derniers résumés depuis la table cron_log (PostgreSQL)
#   - log_get_detail()  : détail d'un jour depuis S3 (stockToolsR/logs/YYYY-MM-DD.rds)
#   - log_list_dates()  : dates disponibles sur S3 (pour un sélecteur de jour)
#
# Dépend de R/0-api_fcts.R pour .s3_obj_exists().

#' Lire les derniers résumés de runs depuis la table `cron_log`
#'
#' @description
#' Retourne les `n` derniers résumés de runs (une ligne par run) depuis la
#' table PostgreSQL `stocktools.cron_log`, triés du plus récent au plus ancien.
#'
#' @param con Connexion DBI PostgreSQL.
#' @param n    Nombre de résumés à retourner (défaut : 10).
#'
#' @return Un tibble avec les colonnes : `run_date`, `statut`, `nb_ok`,
#'   `nb_warn`, `nb_err`, `started_at`, `finished_at`.
#'
#' @importFrom DBI dbGetQuery
#' @importFrom tibble as_tibble
#'
#' @export
log_get_summary <- function(con, n = 10) {
    df <- DBI::dbGetQuery(con, "
        SELECT run_date, statut, nb_ok, nb_warn, nb_err, started_at, finished_at
        FROM stocktools.cron_log
        ORDER BY run_date DESC, run_id DESC
        LIMIT $1
    ", params = list(n))
    tibble::as_tibble(df)
}

#' Lire le détail des logs d'un jour donné (depuis S3)
#'
#' @description
#' Lit le fichier journalier `stockToolsR/logs/YYYY-MM-DD.rds` sur S3 et
#' retourne les lignes de log. Retourne `NULL` si le fichier n'existe pas.
#'
#' @param date      Date au format `"YYYY-MM-DD"` (ou objet Date).
#' @param s3_folder Dossier S3 du package (défaut `"stockToolsR/logs"`).
#'
#' @return Un tibble avec les colonnes `etape`, `statut`, `symbol`, `message`,
#'   ou `NULL` si le fichier du jour n'existe pas.
#'
#' @importFrom s3db s3readRDS_HL
#'
#' @export
log_get_detail <- function(date, s3_folder = "stockToolsR/logs") {
    jour     <- format(as.Date(date), "%Y-%m-%d")
    object_name <- paste0(s3_folder, "/", jour, ".rds")

    if (!.s3_obj_exists(object_name)) {
        return(NULL)
    }
    s3db::s3readRDS_HL(object = object_name)
}

#' Lister les dates des logs disponibles sur S3
#'
#' @description
#' Retourne la liste des dates pour lesquelles un fichier de log journalier
#' existe sur S3 (dans `stockToolsR/logs/`), triée du plus récent au plus
#' ancien. Utile pour un sélecteur de jour dans l'app Shiny.
#'
#' @param s3_folder Dossier S3 du package (défaut `"stockToolsR/logs"`).
#'
#' @return Un vecteur de dates (chaînes `"YYYY-MM-DD"`), ou `character(0)`
#'   si aucun fichier.
#'
#' @importFrom s3db s3listdf_HL
#'
#' @export
log_list_dates <- function(s3_folder = "stockToolsR/logs") {
    files <- s3db::s3listdf_HL(prefix = s3_folder, type = ".rds")
    if (nrow(files) == 0) return(character(0))
    files$Key
}