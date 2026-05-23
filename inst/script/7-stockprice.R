# =============================================================================
# 7-stockprice.R — Mise à jour des prix boursiers
# Variables attendues : con, tickers, today
# =============================================================================
message("-- [7] Mise à jour des prix --")

# tickers non disponibles sur Yahoo Finance
non_available_stockprice <- c("MRO", "SQ", "ATVI", "BIDU", "VIAC", "WBA", "TWTR")

tickers_scope <- setdiff(tickers, non_available_stockprice)

# --- Dernière date de marché disponible (référence via AAPL) ---
latest_market_date <- tq_get("AAPL",
                              get  = "stock.prices",
                              from = today - 7,
                              to   = today) |>
  dplyr::pull(date) |>
  max()

message("Dernière date de marché : ", latest_market_date)

# --- Tickers déjà à jour ---
stockprice_up_to_date <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "stockprice")) |>
  dplyr::filter(symbol %in% tickers_scope) |>
  dplyr::group_by(symbol) |>
  dplyr::summarise(last_date = max(date, na.rm = TRUE)) |>
  dplyr::collect() |>
  dplyr::filter(as.Date(last_date) >= latest_market_date) |>
  dplyr::pull(symbol)

# --- Tickers à mettre à jour --- (incluant les nouveaux tickers)
symbols_to_update <- setdiff(tickers_scope, stockprice_up_to_date)

if (length(symbols_to_update) == 0) {
  message("Tous les prix sont à jour.")
} else {
  message(length(symbols_to_update), " ticker(s) à mettre à jour : ",
          paste(symbols_to_update, collapse = ", "))
  update_stockprice(con, symbols_to_update)
}
#test <- dbReadTable(con,"stockprice")
