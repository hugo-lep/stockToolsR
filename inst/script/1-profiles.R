# =============================================================================
# 1-profiles.R — Vérification et mise à jour des profils des compagnies
# Variables attendues : con, tickers, key_fmp_api
# =============================================================================
message("-- [1] Profils des compagnies --")

# --- 1a. Ajouter les profils manquants ---
cies_in_db <- tbl(con, dbplyr::in_schema("stocktools", "cies_profile_orig")) |> dplyr::pull(symbol) |> unique()
manquants  <- setdiff(tickers, cies_in_db)

if (length(manquants) > 0) {
  message(length(manquants), " profil(s) manquant(s) : ", paste(manquants, collapse = ", "))
  purrr::walk(manquants, fmp_profile_add_to_db, con = con, key_fmp_api = key_fmp_api)
} else {
  message("Tous les profils sont présents.")
}

# --- 1b. Rafraîchissement tournant : les 3 profils les plus anciens ---
# Les profils avec last_updated = NULL passent en premier (anciens avant la colonne)
a_rafraichir <- tbl(con, dbplyr::in_schema("stocktools", "cies_profile_orig")) |>
  dplyr::filter(symbol %in% tickers) |>
  dplyr::select(symbol, last_updated) |>
  dplyr::collect() |>
  dplyr::arrange(last_updated) |>   # NULL sort en premier dans R
  dplyr::slice_head(n = 3) |>
  dplyr::pull(symbol)

message("Rafraîchissement tournant : ", paste(a_rafraichir, collapse = ", "))
purrr::walk(a_rafraichir, fmp_profile_add_to_db, con = con, key_fmp_api = key_fmp_api, force = TRUE)

# --- 1c. Reconstruction de la table build ---
cies_profile_build(con)
message("cies_profile_build reconstruite.")

