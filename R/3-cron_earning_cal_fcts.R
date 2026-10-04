#' Initialiser le fichier de suivi des publications (une seule fois)
#'
#' @description
#' Crée le fichier `cies_order.rds` sur S3 à partir d'un calendrier de publications.
#' Chaque compagnie reçoit des statuts initiaux `"pending"` pour ses 3 états financiers.
#'
#' Cette fonction n'est appelée **qu'une seule fois** lors de l'initialisation du projet.
#' Par la suite, utiliser `update_cies_order()`.
#'
#' @param earning_calendar data.frame contenant au minimum les colonnes `symbol` et `date`
#' @param save_path Nom de l'objet S3 (ex: `"data/cies_order.rds"`)
#'
#' @return Invisiblement, le data.frame `cies_order` initialisé.
#'
#' @importFrom dplyr select rename mutate
#'
#' @export
init_cies_order <- function(earning_calendar, save_path) {

    cies_order <- earning_calendar |>
        dplyr::select(symbol, date) |>
        dplyr::rename(reportDate = date) |>
        dplyr::mutate(
            reportDate     = as.Date(reportDate),
            reportDate_mod = reportDate,
            inc_status     = "pending",
            bs_status      = "pending",
            cf_status      = "pending"
        )

    s3db::s3saveRDS_HL(cies_order, save_path)
    message("cies_order initialisé avec ", nrow(cies_order), " compagnie(s).")

    invisible(cies_order)
}


#' Mettre à jour le fichier de suivi des publications
#'
#' @description
#' Ajoute au fichier `cies_order.rds` (sur S3) les nouvelles compagnies présentes
#' dans le calendrier de publications mais absentes du suivi actuel.
#' Les compagnies déjà présentes ne sont pas modifiées.
#'
#' @param earning_calendar data.frame contenant au minimum les colonnes `symbol` et `date`
#' @param save_path Nom de l'objet S3 (ex: `"data/cies_order.rds"`)
#'
#' @return Invisiblement, le data.frame `cies_order` mis à jour.
#'
#' @importFrom dplyr select rename mutate filter bind_rows arrange
#'
#' @export
update_cies_order <- function(earning_calendar, save_path) {

    cies_order <- s3db::s3readRDS_HL(save_path)

    new_entries <- earning_calendar |>
        dplyr::select(symbol, date) |>
        dplyr::rename(reportDate = date) |>
        dplyr::mutate(
            reportDate     = as.Date(reportDate),
            reportDate_mod = reportDate,
            inc_status     = "pending",
            bs_status      = "pending",
            cf_status      = "pending"
        )

    truly_new <- new_entries |>
        dplyr::filter(!symbol %in% cies_order$symbol)

    if (nrow(truly_new) == 0) {
        message("Aucune nouvelle compagnie à ajouter.")
        return(invisible(cies_order))
    }

    message(nrow(truly_new), " nouvelle(s) compagnie(s) ajoutée(s) : ",
            paste(truly_new$symbol, collapse = ", "))

    cies_order <- cies_order |>
        dplyr::bind_rows(truly_new) |>
        dplyr::arrange(reportDate_mod)

    s3db::s3saveRDS_HL(cies_order, save_path)

    invisible(cies_order)
}
