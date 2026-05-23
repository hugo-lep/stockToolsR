# =============================================================================
# shiny_test2.R — Version complète avec serveur
# Basé sur shiny_test1.R (même layout) — données réelles depuis PostgreSQL
# Prérequis : con doit être défini (via 0-plan.R ou manuellement)
# =============================================================================

library(shiny)
library(bslib)
library(bsicons)
library(dplyr)
library(ggplot2)
library(scales)
library(DBI)
library(lubridate)

choix_seuil <- c("5%" = 0.05, "10%" = 0.10, "15%" = 0.15, "20%" = 0.20)
choix_ans   <- c("1 an" = "1", "3 ans" = "3", "5 ans" = "5", "10 ans" = "10")

metrique_labels <- c(
  "p_to_s"      = "Prix / Ventes",
  "p_to_ebitda" = "Prix / EBITDA",
  "pe"          = "P/E",
  "pe_dil"      = "P/E dilué"
)

# ── Helpers UI ────────────────────────────────────────────────────────────────

ligne_qualite <- function(label, valeur, secteur, signal) {
  cfg <- list(
    vert  = list(classe = "table-success", couleur = "#198754"),
    jaune = list(classe = "table-warning", couleur = "#856404"),
    rouge = list(classe = "table-danger",  couleur = "#dc3545")
  )
  cl <- cfg[[signal]]
  tags$tr(class = cl$classe,
    tags$td(label),
    tags$td(class = "text-end fw-semibold", valeur),
    tags$td(class = "text-end text-muted",  secteur),
    tags$td(class = "text-center",
            tags$span(style = paste0("color:", cl$couleur, "; font-size:1.1rem;"), "●"))
  )
}

section_qualite <- function(label) {
  tags$tr(
    tags$td(colspan = 4, class = "pt-2 pb-0",
            tags$small(tags$b(tags$em(label))))
  )
}

ligne_filtre <- function(id_seuil, id_years, label, selected_years = character(0)) {
  tags$div(
    class = "d-flex align-items-center gap-2 mb-1",
    tags$span(tags$b(label), style = "min-width: 72px;"),
    tags$div(
      style = "width: 72px; flex-shrink: 0;",
      selectInput(id_seuil, NULL, choices = choix_seuil,
                  selected = 0.10, width = "100%", selectize = FALSE)
    ),
    checkboxGroupInput(id_years, NULL,
      choices  = choix_ans,
      selected = selected_years,
      inline   = TRUE
    )
  )
}

# ── UI ────────────────────────────────────────────────────────────────────────

ui <- page_navbar(

  title = "Analyse boursière S&P 500",
  theme = bs_theme(bootswatch = "flatly", base_font = font_google("Inter")),

  # ── Onglet 1 : Filtres ─────────────────────────────────────────────────────
  nav_panel(
    title = "Filtres",
    icon  = bs_icon("sliders"),

    layout_sidebar(
      sidebar = sidebar(
        width = 260,

        selectInput("secteur_f", "Secteur :",
                    choices = "Tous", selected = "Tous"),

        sliderInput("ratio_max_f",
                    label = tags$span(
                      "Position buy → sell :",
                      tags$br(),
                      tags$small(tags$em("0 = bon marché  |  1 = surévalué"))
                    ),
                    min = 0, max = 1, value = 1, step = 0.05)
      ),

      # Grille filtres CAGR
      card(
        card_header(tags$b("Critères de croissance (CAGR)")),
        card_body(
          ligne_filtre("seuil_revenue", "years_revenue", "Revenus",
                       selected_years = c("3", "5")),
          ligne_filtre("seuil_ebitda", "years_ebitda", "EBITDA"),
          ligne_filtre("seuil_eps",    "years_eps",    "EPS dilué")
        )
      ),

      # Compagnies retenues
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          tags$b("Compagnies retenues"),
          textOutput("n_filtrees", inline = TRUE)
        ),
        card_body(
          style = "max-height: 400px; overflow-y: auto; padding: 0.5rem;",
          tableOutput("table_filtrees")
        )
      )
    )
  ),

  # ── Onglet 2 : Résultats ───────────────────────────────────────────────────
  nav_panel(
    title = "Résultats",
    icon  = bs_icon("graph-up"),

    layout_sidebar(
      sidebar = sidebar(
        width = 230,

        selectInput("symbol", "Compagnie :", choices = NULL),

        hr(),

        radioButtons("metrique", tags$b("Bande de valorisation"),
          choices  = metrique_labels,
          selected = "p_to_s"
        ),

        hr(),

        radioButtons("periode", tags$b("Période affichée"),
          choices  = c("1 an" = 1, "3 ans" = 3, "5 ans" = 5, "10 ans" = 10),
          selected = 5,
          inline   = TRUE
        )
      ),

      layout_columns(
        col_widths = c(5, 7),

        # ── Qualité ──────────────────────────────────────────────────────────
        card(
          height = "620px",
          card_header(
            class = "d-flex justify-content-between align-items-center",
            tags$b("Qualité"),
            tags$small(class = "text-muted",
                       textOutput("qualite_secteur", inline = TRUE))
          ),
          card_body(
            style = "overflow-y: auto; padding: 0.5rem;",
            uiOutput("tableau_qualite")
          )
        ),

        # ── Prix ─────────────────────────────────────────────────────────────
        card(
          height = "620px",
          full_screen = TRUE,
          card_header(tags$b("Prix vs bandes de valorisation")),
          card_body(padding = 0,
            plotOutput("valuation_plot", height = "560px")
          )
        )
      )
    )
  )
)

# ── Server ────────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  # ---------------------------------------------------------------------------
  # Chargement des données au démarrage
  # ---------------------------------------------------------------------------

  cagr_data <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "cagr_stmts_build")) |> dplyr::collect()

  profile_data <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "cies_profile_build")) |>
    dplyr::select(symbol, companyname, sector, industry) |>
    dplyr::collect()

  # Dernière valorisation par symbol + ratio moyen buy→sell
  valuation_latest <- DBI::dbGetQuery(con, "
    SELECT DISTINCT ON (symbol)
      symbol, close,
      buy_p_to_s, sell_p_to_s,
      buy_p_to_ebitda, sell_p_to_ebitda,
      buy_pe, sell_pe, buy_pe_dil, sell_pe_dil
    FROM stocktools.valuation_build
    ORDER BY symbol, date DESC
  ") |>
    dplyr::mutate(
      r_pts = ifelse(sell_p_to_s      - buy_p_to_s      > 0,
                     (close - buy_p_to_s)      / (sell_p_to_s      - buy_p_to_s),      NA),
      r_ebd = ifelse(sell_p_to_ebitda - buy_p_to_ebitda > 0,
                     (close - buy_p_to_ebitda) / (sell_p_to_ebitda - buy_p_to_ebitda), NA),
      r_pe  = ifelse(sell_pe          - buy_pe          > 0,
                     (close - buy_pe)          / (sell_pe          - buy_pe),          NA),
      r_ped = ifelse(sell_pe_dil      - buy_pe_dil      > 0,
                     (close - buy_pe_dil)      / (sell_pe_dil      - buy_pe_dil),      NA),
      ratio_moyen = rowMeans(cbind(r_pts, r_ebd, r_pe, r_ped), na.rm = TRUE)
    ) |>
    dplyr::select(symbol, ratio_moyen)

  # Derniers états financiers par symbol pour les ratios de qualité
  stmts_latest <- DBI::dbGetQuery(con, "
    SELECT DISTINCT ON (symbol)
      symbol, is_revenue, is_grossprofit, is_ebitda, is_netincome,
      cf_freecashflow, bs_totalcurrentassets, bs_totalcurrentliabilities
    FROM stocktools.financial_stmts_build
    ORDER BY symbol, date DESC
  ") |>
    dplyr::mutate(
      marge_brute   = is_grossprofit / is_revenue,
      marge_ebitda  = is_ebitda      / is_revenue,
      marge_nette   = is_netincome   / is_revenue,
      fcf_rev       = cf_freecashflow / is_revenue,
      ratio_courant = bs_totalcurrentassets / bs_totalcurrentliabilities
    ) |>
    dplyr::select(symbol, marge_brute, marge_ebitda, marge_nette,
                  fcf_rev, ratio_courant)

  # Table de base : tout joint ensemble
  base_data <- dplyr::inner_join(cagr_data, profile_data, by = "symbol") |>
    dplyr::left_join(valuation_latest, by = "symbol") |>
    dplyr::left_join(stmts_latest,     by = "symbol")

  # Médianes par secteur (référence pour le tableau qualité)
  cols_qualite <- c("marge_brute", "marge_ebitda", "marge_nette",
                    "fcf_rev", "ratio_courant",
                    "cagr_3_is_revenue", "cagr_3_is_ebitda", "cagr_3_is_epsdiluted")

  secteur_medians <- base_data |>
    dplyr::group_by(sector) |>
    dplyr::summarise(dplyr::across(dplyr::all_of(cols_qualite),
                                   ~ median(.x, na.rm = TRUE)),
                     .groups = "drop")

  # Peupler le filtre secteur
  secteurs <- c("Tous", sort(unique(na.omit(base_data$sector))))
  updateSelectInput(session, "secteur_f", choices = secteurs, selected = "Tous")

  # ---------------------------------------------------------------------------
  # Filtrage
  # ---------------------------------------------------------------------------

  filtrer_cagr <- function(df, prefix, seuil, years) {
    if (length(years) == 0) return(df)
    for (y in years) {
      col <- paste0("cagr_", y, "_", prefix)
      if (col %in% names(df))
        df <- df |> dplyr::filter(!is.na(.data[[col]]), .data[[col]] >= seuil)
    }
    df
  }

  df_filtres <- reactive({
    df <- base_data
    if (input$secteur_f != "Tous")
      df <- df |> dplyr::filter(sector == input$secteur_f)
    df <- df |>
      dplyr::filter(is.na(ratio_moyen) | ratio_moyen <= input$ratio_max_f)
    df <- filtrer_cagr(df, "is_revenue",    as.numeric(input$seuil_revenue), input$years_revenue)
    df <- filtrer_cagr(df, "is_ebitda",     as.numeric(input$seuil_ebitda),  input$years_ebitda)
    df <- filtrer_cagr(df, "is_epsdiluted", as.numeric(input$seuil_eps),     input$years_eps)
    df
  })

  # ---------------------------------------------------------------------------
  # Onglet Filtres — outputs
  # ---------------------------------------------------------------------------

  output$n_filtrees <- renderText({
    paste0(nrow(df_filtres()), " compagnies")
  })

  output$table_filtrees <- renderTable({
    df_filtres() |>
      dplyr::arrange(ratio_moyen) |>
      dplyr::transmute(
        Ticker    = symbol,
        Compagnie = companyname,
        Secteur   = sector,
        `Buy→Sell`       = ifelse(is.na(ratio_moyen), "N/D",
                                  scales::percent(ratio_moyen, accuracy = 1)),
        `CAGR Rev. 3 ans` = ifelse(is.na(cagr_3_is_revenue), "N/D",
                                   scales::percent(cagr_3_is_revenue, accuracy = 0.1))
      )
  }, striped = TRUE, hover = TRUE, bordered = FALSE, spacing = "xs",
     width = "100%")

  # Peupler le selectInput symbol dans Résultats à partir des compagnies filtrées
  observe({
    df  <- df_filtres() |> dplyr::arrange(symbol)
    choices <- setNames(df$symbol, paste0(df$symbol, " — ", df$companyname))
    updateSelectInput(session, "symbol", choices = choices,
                      selected = choices[1])
  })

  # ---------------------------------------------------------------------------
  # Onglet Résultats — données du ticker sélectionné
  # ---------------------------------------------------------------------------

  df_symbol <- reactive({
    req(input$symbol)
    dplyr::tbl(con, dbplyr::in_schema("stocktools", "valuation_build")) |>
      dplyr::filter(symbol == !!input$symbol) |>
      dplyr::collect() |>
      dplyr::mutate(date = as.Date(date))
  })

  donnees_symbol <- reactive({
    req(input$symbol)
    base_data |> dplyr::filter(symbol == input$symbol)
  })

  # ---------------------------------------------------------------------------
  # Tableau qualité dynamique
  # ---------------------------------------------------------------------------

  # Signal couleur : vert si la compagnie fait mieux que la médiane du secteur
  # inverse = TRUE pour les métriques où moins est mieux (ex. dette)
  signal_vs <- function(val, ref, inverse = FALSE) {
    if (anyNA(c(val, ref)) || is.nan(val) || is.nan(ref) || ref == 0) return("jaune")
    ratio <- if (inverse) ref / val else val / ref
    if (ratio > 1.05) "vert" else if (ratio < 0.95) "rouge" else "jaune"
  }

  fmt_pct <- function(x) if (is.na(x) || is.nan(x)) "N/D" else scales::percent(x, accuracy = 0.1)
  fmt_x   <- function(x) if (is.na(x) || is.nan(x)) "N/D" else paste0(round(x, 1), "×")

  output$qualite_secteur <- renderText({
    req(nrow(donnees_symbol()) > 0)
    sec <- donnees_symbol()$sector
    if (is.na(sec)) return("")
    paste("vs. secteur", sec)
  })

  output$tableau_qualite <- renderUI({
    req(nrow(donnees_symbol()) > 0)
    d   <- donnees_symbol()
    sec <- d$sector
    ref <- secteur_medians |> dplyr::filter(sector == sec)

    # Si pas de référence sectorielle disponible, tout en jaune
    r <- if (nrow(ref) == 1) ref else
      data.frame(marge_brute = NA, marge_ebitda = NA, marge_nette = NA,
                 fcf_rev = NA, ratio_courant = NA,
                 cagr_3_is_revenue = NA, cagr_3_is_ebitda = NA,
                 cagr_3_is_epsdiluted = NA)

    tags$table(
      class = "table table-sm table-hover mb-0",
      tags$thead(tags$tr(
        tags$th("Ratio"),
        tags$th(class = "text-end", "Compagnie"),
        tags$th(class = "text-end text-muted", "Secteur"),
        tags$th(class = "text-center", "")
      )),
      tags$tbody(
        section_qualite("Rentabilité"),
        ligne_qualite("Marge brute",
                      fmt_pct(d$marge_brute),  fmt_pct(r$marge_brute),
                      signal_vs(d$marge_brute,  r$marge_brute)),
        ligne_qualite("Marge EBITDA",
                      fmt_pct(d$marge_ebitda), fmt_pct(r$marge_ebitda),
                      signal_vs(d$marge_ebitda, r$marge_ebitda)),
        ligne_qualite("Marge nette",
                      fmt_pct(d$marge_nette),  fmt_pct(r$marge_nette),
                      signal_vs(d$marge_nette,  r$marge_nette)),
        section_qualite("Solidité financière"),
        ligne_qualite("Ratio courant",
                      fmt_x(d$ratio_courant),  fmt_x(r$ratio_courant),
                      signal_vs(d$ratio_courant, r$ratio_courant)),
        ligne_qualite("FCF / Revenus",
                      fmt_pct(d$fcf_rev),      fmt_pct(r$fcf_rev),
                      signal_vs(d$fcf_rev,      r$fcf_rev)),
        section_qualite("Croissance"),
        ligne_qualite("CAGR Revenus 3 ans",
                      fmt_pct(d$cagr_3_is_revenue),    fmt_pct(r$cagr_3_is_revenue),
                      signal_vs(d$cagr_3_is_revenue,    r$cagr_3_is_revenue)),
        ligne_qualite("CAGR EBITDA 3 ans",
                      fmt_pct(d$cagr_3_is_ebitda),     fmt_pct(r$cagr_3_is_ebitda),
                      signal_vs(d$cagr_3_is_ebitda,     r$cagr_3_is_ebitda)),
        ligne_qualite("CAGR EPS 3 ans",
                      fmt_pct(d$cagr_3_is_epsdiluted), fmt_pct(r$cagr_3_is_epsdiluted),
                      signal_vs(d$cagr_3_is_epsdiluted, r$cagr_3_is_epsdiluted))
      )
    )
  })

  # ---------------------------------------------------------------------------
  # Graphique bandes de valorisation (métrique unique + période)
  # ---------------------------------------------------------------------------

  output$valuation_plot <- renderPlot({
    req(nrow(df_symbol()) > 0)

    met      <- input$metrique
    date_min <- Sys.Date() - lubridate::years(as.numeric(input$periode))

    cols <- c(
      "buy"     = paste0("buy_",     met),
      "caution" = paste0("caution_", met),
      "sell"    = paste0("sell_",    met)
    )

    df <- df_symbol() |>
      dplyr::filter(date >= date_min) |>
      dplyr::select(date, close, dplyr::all_of(cols)) |>
      dplyr::filter(!is.na(buy), !is.na(sell))

    req(nrow(df) > 0)

    ggplot2::ggplot(df, ggplot2::aes(x = date)) +
      ggplot2::geom_ribbon(ggplot2::aes(ymin = buy, ymax = caution),
                           fill = "#198754", alpha = 0.08) +
      ggplot2::geom_ribbon(ggplot2::aes(ymin = caution, ymax = sell),
                           fill = "#fd7e14", alpha = 0.08) +
      ggplot2::geom_line(ggplot2::aes(y = buy),
                         color = "#198754", linewidth = 0.5, linetype = "dashed") +
      ggplot2::geom_line(ggplot2::aes(y = caution),
                         color = "#fd7e14", linewidth = 0.5, linetype = "dashed") +
      ggplot2::geom_line(ggplot2::aes(y = sell),
                         color = "#dc3545", linewidth = 0.5, linetype = "dashed") +
      ggplot2::geom_line(ggplot2::aes(y = close),
                         color = "black",   linewidth = 0.9) +
      ggplot2::labs(
        title    = paste0(input$symbol, "  —  ", metrique_labels[met]),
        subtitle = paste0("Période : ", input$periode, " an(s)"),
        x = NULL, y = "Prix ($)"
      ) +
      ggplot2::theme_minimal(base_size = 13) +
      ggplot2::theme(panel.grid.minor = element_blank())
  })
}

shinyApp(ui, server)
