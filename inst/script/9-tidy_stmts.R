# =============================================================================
# 9-tidy_stmts.R — Reconstruction de financial_stmts_build
# Variables attendues : con
# =============================================================================
message("-- [9] Reconstruction financial_stmts_build --")

# Colonnes générales (présentes dans les 3 états financiers)
keep_cols_gen <- c(
  "date", "symbol", "reportedcurrency", "cik",
  "filingdate", "accepteddate", "fiscalyear", "period"
)

# Colonnes income statement
keep_cols_is <- c(
  "revenue", "grossprofit", "interestincome", "interestexpense",
  "depreciationandamortization", "ebitda", "ebit", "operatingincome",
  "netincome", "eps", "epsdiluted",
  "weightedaverageshsout", "weightedaverageshsoutdil"
)

# Colonnes balance sheet
keep_cols_bs <- c(
  "totalcurrentassets", "totalnoncurrentassets", "totalassets",
  "totalcurrentliabilities", "totalnoncurrentliabilities", "totalliabilities", "totalstockholdersequity",
  "shorttermdebt", "longtermdebt", "totaldebt"
)

# Colonnes cash flow
keep_cols_cf <- c(
  "stockbasedcompensation",
  "netcashprovidedbyoperatingactivities",
  "netcashprovidedbyinvestingactivities",
  "netcashprovidedbyfinancingactivities",
  "freecashflow"
)

tidy_stmts(con, keep_cols_gen, keep_cols_is, keep_cols_bs, keep_cols_cf)

message("financial_stmts_build reconstruite.")
