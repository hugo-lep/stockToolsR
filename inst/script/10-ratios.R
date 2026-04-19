# =============================================================================
# 10-ratios.R — Calcul des ratios et bandes de valorisation boursière
# Variables attendues : con, tickers
# =============================================================================
message("-- [10] Calcul des ratios de valorisation --")

# --- Bandes de valorisation (P/S, P/EBITDA, PE) ---
valuation_stockprice(con, tickers, window_months = 18)
message("valuation_build mis à jour.")

# --- CAGR des prix boursiers ---
cagr_stockprice(con, tickers, years = c(1, 3, 5, 10))

# --- CAGR des états financiers ---
cagr_stmts(con, tickers)
