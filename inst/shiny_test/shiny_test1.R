# =============================================================================
# shiny_test1.R — Maquette UI (v9 — sans bloc CSS personnalisé)
# Utilise uniquement les classes Bootstrap et les composants bslib natifs
# Server vide — données statiques pour visualiser la structure
# =============================================================================

library(shiny)
library(bslib)
library(bsicons)

choix_seuil <- c("5%" = 0.05, "10%" = 0.10, "15%" = 0.15, "20%" = 0.20)
choix_ans   <- c("1 an" = "1", "3 ans" = "3", "5 ans" = "5", "10 ans" = "10")

# ── Helpers tableau qualité ───────────────────────────────────────────────────

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

tableau_qualite <- function() {
  tags$table(
    class = "table table-sm table-hover mb-0",
    tags$thead(
      tags$tr(
        tags$th("Ratio"),
        tags$th(class = "text-end", "Compagnie"),
        tags$th(class = "text-end text-muted", "Secteur"),
        tags$th(class = "text-center", "")
      )
    ),
    tags$tbody(
      section_qualite("Rentabilité"),
      ligne_qualite("Marge brute",       "45,2 %", "38,1 %", "vert"),
      ligne_qualite("Marge EBITDA",      "28,3 %", "26,9 %", "jaune"),
      ligne_qualite("Marge nette",       "21,1 %", "18,4 %", "vert"),
      ligne_qualite("ROE",               "34,5 %", "22,1 %", "vert"),
      section_qualite("Solidité financière"),
      ligne_qualite("Dette nette / EBITDA", "4,2×",   "2,8×",   "rouge"),
      ligne_qualite("Ratio courant",        "1,4×",   "1,6×",   "jaune"),
      ligne_qualite("FCF / Revenus",        "18,9 %", "14,2 %", "vert"),
      section_qualite("Croissance"),
      ligne_qualite("CAGR Revenus 3 ans", "14,2 %", "9,8 %",  "vert"),
      ligne_qualite("CAGR EBITDA 3 ans",  "10,8 %", "11,3 %", "jaune"),
      ligne_qualite("CAGR EPS 3 ans",     "11,3 %", "12,1 %", "jaune")
    )
  )
}

# ── Ligne de filtre CAGR (métrique + seuil + années) ─────────────────────────
# selectize = FALSE : <select> natif, compact, respecte la largeur sans CSS

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
                    choices  = c("Tous", "Technology", "Healthcare", "Financials"),
                    selected = "Tous"),

        sliderInput("ratio_max_f",
                    label = tags$span(
                      "Position buy → sell :",
                      tags$br(),
                      tags$small(tags$em("0 = bon marché  |  1 = surévalué"))
                    ),
                    min = 0, max = 1, value = 1, step = 0.05),

      ),

      # Grille filtres CAGR — une ligne par métrique, pas de CSS externe
      card(
        card_header(tags$b("Critères de croissance (CAGR)")),
        card_body(
          ligne_filtre("seuil_revenue", "years_revenue", "Revenus",
                       selected_years = c("3", "5")),
          ligne_filtre("seuil_ebitda", "years_ebitda", "EBITDA"),
          ligne_filtre("seuil_eps",    "years_eps",    "EPS dilué")
        )
      ),

      # Aperçu des compagnies retenues
      card(
        card_header(tags$b("Compagnies retenues (47)")),
        card_body(
          style = "max-height: 350px; overflow-y: auto;",
          tags$p(tags$em(class = "text-muted",
            "(tableau : symbol, nom, secteur, ratio buy→sell, CAGR...)"
          ))
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

        selectInput("symbol", "Compagnie :",
                    choices  = c("AAPL — Apple Inc.",
                                 "MSFT — Microsoft Corp.",
                                 "GOOGL — Alphabet Inc."),
                    selected = "AAPL — Apple Inc."),

        hr(),

        radioButtons("metrique", tags$b("Bande de valorisation"),
          choices  = c("Prix / Ventes"  = "p_to_s",
                       "Prix / EBITDA"  = "p_to_ebitda",
                       "P/E"            = "pe",
                       "P/E dilué"      = "pe_dil"),
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
            tags$small(class = "text-muted", "vs. secteur Technology")
          ),
          card_body(
            style = "overflow-y: auto; padding: 0.5rem;",
            tableau_qualite()
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

server <- function(input, output, session) {}

shinyApp(ui, server)
