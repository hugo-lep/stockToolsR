# Exporte deux fonctions :
#   mod_finance_ui(id)       — panneaux nav à insérer dans un page_navbar()
#   mod_finance_server(id, con) — logique serveur (nécessite une connexion DBI)


# ── Constantes internes ───────────────────────────────────────────────────────

.choix_seuil <- c("5%" = 0.05, "10%" = 0.10, "15%" = 0.15, "20%" = 0.20)
.choix_ans   <- c("1 an" = "1", "3 ans" = "3", "5 ans" = "5", "10 ans" = "10")

.metrique_choices <- c(
  "Prix / Ventes"  = "p_to_s",
  "Prix / EBITDA"  = "p_to_ebitda",
  "P/E"            = "pe",
  "P/E dilué"      = "pe_dil"
)
# valeur → label (pour le titre du graphique)
.metrique_labels <- setNames(names(.metrique_choices), .metrique_choices)

# ── Helpers UI (non exportés) ─────────────────────────────────────────────────

#' Ligne colorée dans le tableau qualité
#' @noRd
.ligne_qualite <- function(label, valeur, secteur, signal) {
  cfg <- list(
    vert  = list(classe = "table-success", couleur = "#198754"),
    jaune = list(classe = "table-warning", couleur = "#856404"),
    rouge = list(classe = "table-danger",  couleur = "#dc3545")
  )
  cl <- cfg[[signal]]
  shiny::tags$tr(class = cl$classe,
    shiny::tags$td(label),
    shiny::tags$td(class = "text-end fw-semibold", valeur),
    shiny::tags$td(class = "text-end text-muted",  secteur),
    shiny::tags$td(class = "text-center",
      shiny::tags$span(
        style = paste0("color:", cl$couleur, "; font-size:1.1rem;"), "●"
      )
    )
  )
}

#' En-tête de section dans le tableau qualité
#' @noRd
.section_qualite <- function(label) {
  shiny::tags$tr(
    shiny::tags$td(
      colspan = 4, class = "pt-2 pb-0",
      shiny::tags$small(shiny::tags$b(shiny::tags$em(label)))
    )
  )
}

#' Ligne de filtre CAGR (seuil % + cases années)
#'
#' @param ns         Fonction de namespace du module (`NS(id)`)
#' @param id_seuil   ID du selectInput seuil (sans namespace)
#' @param id_years   ID du checkboxGroupInput années (sans namespace)
#' @param label      Libellé affiché
#' @param selected_years Années cochées par défaut
#' @noRd
.ligne_filtre <- function(ns, id_seuil, id_years, label,
                          selected_years = character(0)) {
  shiny::tags$div(
    class = "d-flex align-items-center gap-2 mb-1",
    shiny::tags$span(shiny::tags$b(label), style = "min-width: 72px;"),
    shiny::tags$div(
      style = "width: 72px; flex-shrink: 0;",
      shiny::selectInput(ns(id_seuil), NULL,
                         choices   = .choix_seuil,
                         selected  = 0.10,
                         width     = "100%",
                         selectize = FALSE)
    ),
    shiny::checkboxGroupInput(ns(id_years), NULL,
      choices  = .choix_ans,
      selected = selected_years,
      inline   = TRUE
    )
  )
}

# ── UI ────────────────────────────────────────────────────────────────────────

#' Onglet Filtres du module analyse boursière
#'
#' Retourne un `bslib::nav_panel` "Filtres" à insérer dans un `navset_*` parent.
#' Utiliser le même `id` que `mod_finance_ui2()` et `mod_finance_server()`.
#'
#' @param id Identifiant du module (chaîne de caractères)
#'
#' @return Un `bslib::nav_panel`
#'
#' @importFrom shiny NS tags textOutput tableOutput selectInput sliderInput
#'   checkboxGroupInput
#' @importFrom bslib nav_panel layout_sidebar sidebar card card_header card_body
#' @importFrom bsicons bs_icon
#'
#' @export
mod_finance_ui1 <- function(id) {
  ns <- shiny::NS(id)

  bslib::nav_panel(
    title = "Filtres",
    icon  = bsicons::bs_icon("sliders"),

    bslib::layout_sidebar(
      sidebar = bslib::sidebar(
        open  = "always",
        width = 260,

        shiny::selectInput(ns("secteur_f"), "Secteur :",
                           choices = "Tous", selected = "Tous"),

        shiny::sliderInput(ns("ratio_max_f"),
          label = shiny::tags$span(
            "Position buy → sell :",
            shiny::tags$br(),
            shiny::tags$small(shiny::tags$em("0 = bon marché  |  1 = surévalué"))
          ),
          min = 0, max = 1, value = 1, step = 0.05)
      ),

      # Grille filtres CAGR
      bslib::card(
        bslib::card_header(shiny::tags$b("Critères de croissance (CAGR)")),
        bslib::card_body(
          .ligne_filtre(ns, "seuil_revenue", "years_revenue", "Revenus",
                        selected_years = c("3", "5")),
          .ligne_filtre(ns, "seuil_ebitda",  "years_ebitda",  "EBITDA"),
          .ligne_filtre(ns, "seuil_eps",      "years_eps",     "EPS dilué")
        )
      ),

      # Compagnies retenues
      bslib::card(
        bslib::card_header(
          class = "d-flex justify-content-between align-items-center",
          shiny::tags$b("Compagnies retenues"),
          shiny::textOutput(ns("n_filtrees"), inline = TRUE)
        ),
        bslib::card_body(
          style = "max-height: 400px; overflow-y: auto; padding: 0.5rem;",
          shiny::tableOutput(ns("table_filtrees"))
        )
      )
    )
  )
}

#' Onglet Résultats du module analyse boursière
#'
#' Retourne un `bslib::nav_panel` "Résultats" à insérer dans un `navset_*` parent.
#' Utiliser le même `id` que `mod_finance_ui1()` et `mod_finance_server()`.
#'
#' @param id Identifiant du module (chaîne de caractères)
#'
#' @return Un `bslib::nav_panel`
#'
#' @importFrom shiny NS tags textOutput uiOutput plotOutput selectInput
#'   radioButtons hr
#' @importFrom bslib nav_panel layout_sidebar sidebar card card_header card_body
#'   layout_columns
#' @importFrom bsicons bs_icon
#'
#' @export
mod_finance_ui2 <- function(id) {
  ns <- shiny::NS(id)

  bslib::nav_panel(
    title = "Résultats",
    icon  = bsicons::bs_icon("graph-up"),

    bslib::layout_sidebar(
      sidebar = bslib::sidebar(
        open  = "always",
        width = 230,

        shiny::selectInput(ns("symbol"), "Compagnie :", choices = NULL),

        shiny::hr(),

        shiny::radioButtons(ns("metrique"), shiny::tags$b("Bande de valorisation"),
          choices  = .metrique_choices,
          selected = "p_to_s"
        ),

        shiny::hr(),

        shiny::radioButtons(ns("periode"), shiny::tags$b("Période affichée"),
          choices  = c("1 an" = 1, "3 ans" = 3, "5 ans" = 5, "10 ans" = 10),
          selected = 5,
          inline   = TRUE
        )
      ),

      bslib::layout_columns(
        col_widths = c(5, 7),

        # ── Qualité ──────────────────────────────────────────────────────────
        bslib::card(
          height = "620px",
          bslib::card_header(
            class = "d-flex justify-content-between align-items-center",
            shiny::tags$b("Qualité"),
            shiny::tags$small(class = "text-muted",
              shiny::textOutput(ns("qualite_secteur"), inline = TRUE))
          ),
          bslib::card_body(
            style = "overflow-y: auto; padding: 0.5rem;",
            shiny::uiOutput(ns("tableau_qualite"))
          )
        ),

        # ── Prix ─────────────────────────────────────────────────────────────
        bslib::card(
          height = "620px",
          full_screen = TRUE,
          bslib::card_header(shiny::tags$b("Prix vs bandes de valorisation")),
          bslib::card_body(padding = 0,
            shiny::plotOutput(ns("valuation_plot"), height = "560px")
          )
        )
      )
    )
  )
}

#' UI complète du module analyse boursière (raccourci)
#'
#' Combine `mod_finance_ui1()` et `mod_finance_ui2()` dans un `bslib::navset_bar()`
#' prêt à être inséré dans un conteneur de page (ex: `bslib::page_fluid()`).
#'
#' @param id Identifiant du module (chaîne de caractères)
#'
#' @return Un `bslib::navset_bar`
#'
#' @importFrom bslib navset_bar
#'
#' @export
mod_finance_ui <- function(id) {
  bslib::navset_bar(
    mod_finance_ui1(id),
    mod_finance_ui2(id)
  )
}

# ── Server ────────────────────────────────────────────────────────────────────

#' Serveur du module analyse boursière
#'
#' @param id  Identifiant du module (doit correspondre à celui passé à `mod_finance_ui`)
#' @param con Connexion DBI active (PostgreSQL)
#'
#' @importFrom shiny moduleServer reactive req observe renderText renderTable
#'   renderUI renderPlot updateSelectInput
#' @importFrom dplyr tbl collect select filter mutate arrange transmute inner_join
#'   left_join group_by summarise across all_of any_of
#' @importFrom DBI dbGetQuery
#' @importFrom scales percent
#' @importFrom ggplot2 ggplot aes geom_ribbon geom_line labs theme_minimal theme
#'   element_blank
#' @importFrom lubridate years
#'
#' @export
mod_finance_server <- function(id, con) {
  shiny::moduleServer(id, function(input, output, session) {

    # -------------------------------------------------------------------------
    # Chargement des données au démarrage
    # -------------------------------------------------------------------------

    cagr_data <- dplyr::tbl(con, "cagr_stmts_build") |> dplyr::collect()

    profile_data <- dplyr::tbl(con, "cies_profile_build") |>
      dplyr::select(symbol, companyname, sector, industry) |>
      dplyr::collect()

    # Dernière valorisation par symbol + ratio moyen buy→sell
    valuation_latest <- DBI::dbGetQuery(con, "
      SELECT DISTINCT ON (symbol)
        symbol, close,
        buy_p_to_s, sell_p_to_s,
        buy_p_to_ebitda, sell_p_to_ebitda,
        buy_pe, sell_pe, buy_pe_dil, sell_pe_dil
      FROM valuation_build
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
      FROM financial_stmts_build
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

    # Peupler le filtre secteur dès que l'input existe côté client
    # (observeEvent attend que secteur_f soit rendu, robuste au lazy rendering)
    secteurs <- c("Tous", sort(unique(na.omit(base_data$sector))))
    shiny::observeEvent(input$secteur_f, {
      shiny::updateSelectInput(session, "secteur_f",
                               choices  = secteurs,
                               selected = "Tous")
    }, once = TRUE, ignoreNULL = TRUE, ignoreInit = FALSE)

    # -------------------------------------------------------------------------
    # Helpers serveur
    # -------------------------------------------------------------------------

    # Filtre CAGR sur un préfixe de colonne et un vecteur d'années
    filtrer_cagr <- function(df, prefix, seuil, years) {
      if (length(years) == 0) return(df)
      for (y in years) {
        col <- paste0("cagr_", y, "_", prefix)
        if (col %in% names(df))
          df <- df |> dplyr::filter(!is.na(.data[[col]]), .data[[col]] >= seuil)
      }
      df
    }

    # Signal couleur : vert si la compagnie surpasse la médiane du secteur (±5 %)
    signal_vs <- function(val, ref, inverse = FALSE) {
      if (anyNA(c(val, ref)) || is.nan(val) || is.nan(ref) || ref == 0)
        return("jaune")
      ratio <- if (inverse) ref / val else val / ref
      if (ratio > 1.05) "vert" else if (ratio < 0.95) "rouge" else "jaune"
    }

    fmt_pct <- function(x)
      if (is.na(x) || is.nan(x)) "N/D" else scales::percent(x, accuracy = 0.1)
    fmt_x <- function(x)
      if (is.na(x) || is.nan(x)) "N/D" else paste0(round(x, 1), "×")

    # -------------------------------------------------------------------------
    # Filtrage réactif
    # -------------------------------------------------------------------------

    df_filtres <- shiny::reactive({
      shiny::req(input$secteur_f, input$ratio_max_f,
                 input$seuil_revenue, input$seuil_ebitda, input$seuil_eps)
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

    # -------------------------------------------------------------------------
    # Onglet Filtres — outputs
    # -------------------------------------------------------------------------

    output$n_filtrees <- shiny::renderText({
      paste0(nrow(df_filtres()), " compagnies")
    })

    output$table_filtrees <- shiny::renderTable({
      df_filtres() |>
        dplyr::arrange(ratio_moyen) |>
        dplyr::transmute(
          Ticker           = symbol,
          Compagnie        = companyname,
          Secteur          = sector,
          `Buy→Sell`  = ifelse(is.na(ratio_moyen), "N/D",
                                    scales::percent(ratio_moyen, accuracy = 1)),
          `CAGR Rev. 3 ans` = ifelse(is.na(cagr_3_is_revenue), "N/D",
                                     scales::percent(cagr_3_is_revenue, accuracy = 0.1))
        )
    }, striped = TRUE, hover = TRUE, bordered = FALSE, spacing = "xs",
       width = "100%")

    # Synchroniser le selectInput symbol avec les compagnies filtrées
    shiny::observe({
      df <- df_filtres() |> dplyr::arrange(symbol)
      if (nrow(df) == 0) {
        shiny::updateSelectInput(session, "symbol",
                                 choices = c("Aucune compagnie" = ""))
        return()
      }
      choices <- setNames(df$symbol, paste0(df$symbol, " — ", df$companyname))
      shiny::updateSelectInput(session, "symbol",
                               choices  = choices,
                               selected = choices[1])
    })

    # -------------------------------------------------------------------------
    # Onglet Résultats — données du ticker sélectionné
    # -------------------------------------------------------------------------

    # Historique complet de valorisation pour le graphique
    df_symbol <- shiny::reactive({
      shiny::req(input$symbol)
      dplyr::tbl(con, "valuation_build") |>
        dplyr::filter(symbol == !!input$symbol) |>
        dplyr::collect() |>
        dplyr::mutate(date = as.Date(date))
    })

    # Ligne unique de base_data pour le tableau qualité
    donnees_symbol <- shiny::reactive({
      shiny::req(input$symbol)
      base_data |> dplyr::filter(symbol == input$symbol)
    })

    # -------------------------------------------------------------------------
    # Tableau qualité dynamique
    # -------------------------------------------------------------------------

    output$qualite_secteur <- shiny::renderText({
      shiny::req(nrow(donnees_symbol()) > 0)
      sec <- donnees_symbol()$sector
      if (is.na(sec)) return("")
      paste("vs. secteur", sec)
    })

    output$tableau_qualite <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol()) > 0)
      d   <- donnees_symbol()
      sec <- d$sector
      ref <- secteur_medians |> dplyr::filter(sector == sec)

      # Référence vide si secteur inconnu
      r <- if (nrow(ref) == 1) ref else
        data.frame(marge_brute = NA, marge_ebitda = NA, marge_nette = NA,
                   fcf_rev = NA, ratio_courant = NA,
                   cagr_3_is_revenue = NA, cagr_3_is_ebitda = NA,
                   cagr_3_is_epsdiluted = NA)

      shiny::tags$table(
        class = "table table-sm table-hover mb-0",
        shiny::tags$thead(shiny::tags$tr(
          shiny::tags$th("Ratio"),
          shiny::tags$th(class = "text-end", "Compagnie"),
          shiny::tags$th(class = "text-end text-muted", "Secteur"),
          shiny::tags$th(class = "text-center", "")
        )),
        shiny::tags$tbody(
          .section_qualite("Rentabilité"),
          .ligne_qualite("Marge brute",
                         fmt_pct(d$marge_brute),  fmt_pct(r$marge_brute),
                         signal_vs(d$marge_brute,  r$marge_brute)),
          .ligne_qualite("Marge EBITDA",
                         fmt_pct(d$marge_ebitda), fmt_pct(r$marge_ebitda),
                         signal_vs(d$marge_ebitda, r$marge_ebitda)),
          .ligne_qualite("Marge nette",
                         fmt_pct(d$marge_nette),  fmt_pct(r$marge_nette),
                         signal_vs(d$marge_nette,  r$marge_nette)),
          .section_qualite("Solidité financière"),
          .ligne_qualite("Ratio courant",
                         fmt_x(d$ratio_courant),  fmt_x(r$ratio_courant),
                         signal_vs(d$ratio_courant, r$ratio_courant)),
          .ligne_qualite("FCF / Revenus",
                         fmt_pct(d$fcf_rev),      fmt_pct(r$fcf_rev),
                         signal_vs(d$fcf_rev,      r$fcf_rev)),
          .section_qualite("Croissance"),
          .ligne_qualite("CAGR Revenus 3 ans",
                         fmt_pct(d$cagr_3_is_revenue),    fmt_pct(r$cagr_3_is_revenue),
                         signal_vs(d$cagr_3_is_revenue,    r$cagr_3_is_revenue)),
          .ligne_qualite("CAGR EBITDA 3 ans",
                         fmt_pct(d$cagr_3_is_ebitda),     fmt_pct(r$cagr_3_is_ebitda),
                         signal_vs(d$cagr_3_is_ebitda,     r$cagr_3_is_ebitda)),
          .ligne_qualite("CAGR EPS 3 ans",
                         fmt_pct(d$cagr_3_is_epsdiluted), fmt_pct(r$cagr_3_is_epsdiluted),
                         signal_vs(d$cagr_3_is_epsdiluted, r$cagr_3_is_epsdiluted))
        )
      )
    })

    # -------------------------------------------------------------------------
    # Graphique bandes de valorisation
    # -------------------------------------------------------------------------

    output$valuation_plot <- shiny::renderPlot({
      shiny::req(nrow(df_symbol()) > 0)

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

      shiny::req(nrow(df) > 0)

      ggplot2::ggplot(df, ggplot2::aes(x = date)) +
#        ggplot2::geom_ribbon(ggplot2::aes(ymin = buy, ymax = caution),
#                             fill = "#198754", alpha = 0.08) +
#        ggplot2::geom_ribbon(ggplot2::aes(ymin = caution, ymax = sell),
#                             fill = "#fd7e14", alpha = 0.08) +
        ggplot2::geom_line(ggplot2::aes(y = buy),
                           color = "green", linewidth = 0.5) +
        ggplot2::geom_line(ggplot2::aes(y = caution),
                           color = "orange", linewidth = 0.5) +
        ggplot2::geom_line(ggplot2::aes(y = sell),
                           color = "red", linewidth = 0.5) +
        ggplot2::geom_line(ggplot2::aes(y = close),
                           color = "black",   linewidth = 0.9) +
        ggplot2::labs(
          title    = paste0(input$symbol, "  —  ", .metrique_labels[met]),
          subtitle = paste0("Période : ", input$periode, " an(s)"),
          x = NULL, y = "Prix ($)"
        ) +
        ggplot2::theme_minimal(base_size = 13) +
        ggplot2::theme(panel.grid.minor = ggplot2::element_blank())
    })

  })
}

