# =============================================================================
# 01_profiles.R — Profils des compagnies (version révisée)
# =============================================================================
#
# Réécriture de l'étape 1 du cron : vérification et mise à jour des profils
# des compagnies dans cies_profile_orig, puis reconstruction de
# cies_profile_build.
#
# Utilise le helper DRY fmp_get() (R/0-api_fcts.R) pour les appels FMP :
#   - clé API par header (pas dans l'URL)
#   - retry + log des erreurs
#   - Sys.sleep(0.2) pour respecter la limite FMP (300 appels/min)
#
# Variables attendues (posées par 0-plan.R) :
#   con, tickers, key_fmp_api
#   log_env (initialisé par init_log())
#
# Dépend de : R/0-api_fcts.R (chargé par devtools::load_all())
# =============================================================================

message("-- [1] Profils des compagnies --")
log_append(etape = "profiles", statut = "OK", message = "Début étape profils")

# =============================================================================
# Helper local : upsert d'un profil (avec transaction si remplacement)
# =============================================================================
#
# @param symbol      Ticker à traiter
# @param con         Connexion DBI
# @param key_fmp_api Clé API FMP
# @param force       Logique. TRUE = remplacer le profil existant (transaction).
#
# @return TRUE si le profil a été ajouté/remplacé, FALSE sinon (échec ou skip).
upsert_profile <- function(symbol, con, key_fmp_api, force = FALSE) {

    # Récupération via le helper DRY
    profile <- fmp_get(
        endpoint    = "profile",
        params      = list(symbol = symbol),
        key_fmp_api = key_fmp_api
    )

    if (is.null(profile) || nrow(profile) == 0) {
        log_append("profiles", "ERROR", symbol, "Profil introuvable ou échec API")
        message("    ✖ ", symbol, " : profil introuvable ou échec API")
        return(FALSE)
    }

    # Normalisation : noms de colonnes en minuscules
    names(profile) <- tolower(names(profile))

    if (!"symbol" %in% names(profile)) {
        profile$symbol <- symbol
    }
    profile$last_updated <- Sys.Date()

    # Existe-t-il déjà une ligne pour ce symbole ?
    existe <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "cies_profile_orig")) |>
        dplyr::filter(symbol == !!symbol) |>
        dplyr::summarise(n = dplyr::n()) |>
        dplyr::collect() |>
        dplyr::pull(n) > 0

    if (existe && force) {
        # Remplacement atomique : DELETE + INSERT dans une transaction
        tryCatch(
            DBI::dbWithTransaction(con, {
                DBI::dbExecute(
                    con,
                    "DELETE FROM stocktools.cies_profile_orig WHERE symbol = $1",
                    params = list(symbol)
                )
                DBI::dbWriteTable(
                    con,
                    DBI::Id(schema = "stocktools", table = "cies_profile_orig"),
                    profile,
                    append = TRUE
                )
            }),
            error = function(e) {
                log_append("profiles", "ERROR", symbol,
                           paste0("Échec transaction profil : ", conditionMessage(e)))
                message("    ✖ ", symbol, " : échec transaction (", conditionMessage(e), ")")
                return(FALSE)
            }
        )
    } else {
        # Insertion simple (nouveau profil, ou force=FALSE)
        tryCatch(
            DBI::dbWriteTable(
                con,
                DBI::Id(schema = "stocktools", table = "cies_profile_orig"),
                profile,
                append = TRUE
            ),
            error = function(e) {
                log_append("profiles", "ERROR", symbol,
                            paste0("Échec insertion : ", conditionMessage(e)))
                message("    ✖ ", symbol, " : échec insertion (", conditionMessage(e), ")")
                return(FALSE)
            }
        )
    }

    log_append("profiles", "OK", symbol, message = "Profil ajouté/remplacé")
    message("    ✔ ", symbol, " profil actualisé")
    TRUE
}

# ---------------------------------------------------------------------------
# 1a. Ajouter les profils manquants
# ---------------------------------------------------------------------------
cies_in_db <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "cies_profile_orig")) |>
    dplyr::pull(symbol) |>
    unique()

manquants <- setdiff(tickers, cies_in_db)

if (length(manquants) > 0) {
    message("  ", length(manquants), " profil(s) manquant(s) : ",
            paste(manquants, collapse = ", "))
    log_append("profiles", "OK",
               message = paste0(length(manquants), " profil(s) manquant(s)"))
    for (sym in manquants) {
        upsert_profile(symbol = sym, con = con, key_fmp_api = key_fmp_api)
        Sys.sleep(0.2)   # limite FMP : 300 appels/min
    }
} else {
    message("  Tous les profils sont présents.")
    log_append("profiles", "OK", message = "Tous les profils sont présents")
}

# ---------------------------------------------------------------------------
# 1b — Rafraîchissement tournant des 3 profils les plus anciens
# ---------------------------------------------------------------------------
# Les profils avec last_updated = NULL passent en premier (anciens avant la colonne)
a_rafraichir <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "cies_profile_orig")) |>
    dplyr::filter(symbol %in% tickers) |>
    dplyr::select(symbol, last_updated) |>
    dplyr::collect() |>
    dplyr::arrange(last_updated) |>   # NULL sort en premier dans R
    dplyr::slice_head(n = 3) |>
    dplyr::pull(symbol)

message("  Rafraîchissement tournant : ", paste(a_rafraichir, collapse = ", "))
log_append("profiles", "OK",
           message = paste0("Rafraîchissement tournant : ",
                            paste(a_rafraichir, collapse = ", ")))

for (sym in a_rafraichir) {
    upsert_profile(symbol = sym, con = con, key_fmp_api = key_fmp_api, force = TRUE)
    Sys.sleep(0.2)
}

# ---------------------------------------------------------------------------
# 1c — Reconstruction de la table build
# ---------------------------------------------------------------------------
build_data <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "cies_profile_orig")) |>
    dplyr::select(symbol, companyname, currency, cik, cusip, exchange, industry,
                  website, description, sector, image, last_updated) |>
    dplyr::collect()

tryCatch(
    DBI::dbWriteTable(
        con,
        DBI::Id(schema = "stocktools", table = "cies_profile_build"),
        build_data,
        overwrite = TRUE
    ),
    error = function(e) {
        log_append("profiles", "ERROR",
                   message = paste0("Échec reconstruction build : ",
                                    conditionMessage(e)))
        stop("cies_profile_build : échec de reconstruction")
    }
)

log_append("profiles", "OK", message = "cies_profile_build reconstruite")
message("  cies_profile_build reconstruite.")
