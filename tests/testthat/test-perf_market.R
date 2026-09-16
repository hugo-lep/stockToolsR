# test-perf_market.R — Tests de perf_from_prices() et perf_market()

# Jeu de prix factice (dates croissantes) pour deux compagnies.
# AAPL : 100,101,102,103,104,105  (6 jours)
# MSFT : 50,50,50,50,50,50        (6 jours, prix constant)
make_prices <- function() {
    dates <- as.Date("2026-01-01") + 0:5
    data.frame(
        symbol = c(rep("AAPL", 6), rep("MSFT", 6)),
        date   = rep(dates, 2),
        close  = c(100, 101, 102, 103, 104, 105,   # AAPL
                    50, 50, 50, 50, 50, 50)        # MSFT
    )
}

test_that("perf_from_prices calcule correctement la performance 1 jour", {
    perfs <- stockToolsR:::perf_from_prices(make_prices(), horizons = c(1))

    expect_true("perf_1" %in% names(perfs))
    # AAPL : (105 - 104) / 104 = 0.009615
    expect_equal(perfs$perf_1[perfs$symbol == "AAPL"], 1 / 104, tolerance = 1e-9)
    # MSFT : constant -> 0
    expect_equal(perfs$perf_1[perfs$symbol == "MSFT"], 0, tolerance = 1e-9)
})

test_that("perf_from_prices calcule plusieurs horizons", {
    prices <- make_prices()
    perfs <- stockToolsR:::perf_from_prices(prices, horizons = c(1, 5))

    # AAPL : 6 lignes, perf 5j = (105 - 100) / 100 = 0.05
    expect_equal(perfs$perf_5[perfs$symbol == "AAPL"], 0.05, tolerance = 1e-9)
})

test_that("perf_from_prices renvoie NA quand pas assez de lignes", {
    # Compagnie avec une seule ligne de prix
    prices <- data.frame(
        symbol = "ONLY",
        date   = as.Date("2026-01-01"),
        close  = 42
    )
    perfs <- stockToolsR:::perf_from_prices(prices, horizons = c(1, 21))

    # Avec 1 seule ligne, aucun horizon calculable
    expect_true(is.na(perfs$perf_1[1]))
    expect_true(is.na(perfs$perf_21[1]))
})

test_that("perf_market agrège en moyenne toutes les compagnies", {
    df <- stockToolsR:::perf_from_prices(make_prices(), horizons = c(1))
    # enrichir avec secteur (perf_market utilise df et ignore con si fourni)
    df$sector <- c("Tech", "Tech")

    res <- perf_market(df = df, fun = mean)
    # AAPL perf_1 = 1/104, MSFT = 0 -> moyenne = (1/104)/2
    expect_equal(res$perf_1, (1 / 104) / 2, tolerance = 1e-9)
})

test_that("perf_market_median", {
    df <- stockToolsR:::perf_from_prices(make_prices(), horizons = c(1))
    df$sector <- c("Tech", "Tech")

    res <- perf_market(df = df, fun = median)
    expect_equal(res$perf_1, stats::median(c(1 / 104, 0)), tolerance = 1e-9)
})

test_that("perf_sector agrège par secteur", {
    df <- stockToolsR:::perf_from_prices(make_prices(), horizons = c(1))
    # Deux secteurs : Tech (AAPL), Industrie (MSFT)
    df$sector <- c("Tech", "Industrie")

    res <- perf_sector(df = df, fun = mean)
    expect_equal(nrow(res), 2)
    expect_equal(res$n_companies[res$sector == "Tech"], 1)
    expect_equal(res$perf_1[res$sector == "Tech"], 1 / 104, tolerance = 1e-9)
    expect_equal(res$perf_1[res$sector == "Industrie"], 0, tolerance = 1e-9)
})

test_that("perf_market accepte un df pré-calculé sans connexion", {
    df <- stockToolsR:::perf_from_prices(make_prices(), horizons = c(1))
    df$sector <- "Tech"
    # doit fonctionner sans `con`
    res <- perf_market(df = df, fun = mean)
    expect_true(!is.null(res$perf_1))
})