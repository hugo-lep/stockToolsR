# =============================================================================
# mod_finance5.R — Module Shiny : analyse boursière (version 5)
#
# Layout deux sections (CSS grid) sans scroll :
#   TOP    — Qualité : Marges | ROA/ROE + Croissance | Structure financière
#   BOTTOM — Prix    : Valorisation | Graphique + boîtes | Dividendes
#
# Réutilise les helpers définis dans mod_finance4.R (même namespace package) :
#   .ligne_qualite, .section_qualite, .lq2, .sig2, .fmt_pct2, .fmt_x2,
#   .fmt_num2, .sig_vs_prix3, .td_cagr3, .td_ref3, .metric_val_cols3,
#   .filter_defs2, .presets_defs3, .build_checkbox_ui2, .build_sliders_actifs2
#
# Fonctions exportées :
#   mod_finance5_ui1(id)         — nav_panel "Filtres"
#   mod_finance5_ui2(id)         — nav_panel "Détail compagnie"
#   mod_finance5_ui(id)          — navset_bar wrapper
#   mod_finance5_server(id, con) — logique serveur
# =============================================================================

# ── UI 1 — Onglet Filtres ────────────────────────────────────────────────────

#' Onglet Filtres du module analyse boursière v5
#'
#' @param id Identifiant du module
#' @return `bslib::nav_panel`
#' @importFrom shiny NS tags tagList textOutput uiOutput checkboxInput selectInput
#' @importFrom bslib nav_panel layout_sidebar sidebar card card_header card_body
#' @importFrom bsicons bs_icon
#' @export
mod_finance5_ui1 <- function(id) {
  ns <- shiny::NS(id)

  bslib::nav_panel(
    title = "Filtres",
    shiny::tags$style(shiny::HTML(
      ".irs-min, .irs-max { display: none !important; }"
    )),
    icon = bsicons::bs_icon("sliders"),

    bslib::layout_sidebar(
      fill = TRUE,

      # ── Sidebar Sélection ─────────────────────────────────────────────────
      sidebar = bslib::sidebar(
        title = "Sélection",
        width = 230,

        shiny::selectInput(ns("preset"), "Pr\u00e9r\u00e9glage :",
                           choices  = c("Aucun" = "", names(.presets_defs3)),
                           selected = ""),
        shiny::tags$hr(class = "my-1"),
        shiny::selectInput(ns("secteur_f"), "Secteur :",
                           choices = "Tous", selected = "Tous"),
        shiny::tags$hr(class = "my-1"),
        .build_checkbox_ui2(ns, .filter_defs2),
        shiny::tags$hr(class = "my-1"),
        shiny::checkboxInput(ns("avec_div"), "Avec dividende", value = FALSE),
        shiny::uiOutput(ns("div_checkbox_ui"))
      ),

      bslib::layout_sidebar(
        fill = TRUE,

        # ── Sidebar Filtres actifs ─────────────────────────────────────────
        sidebar = bslib::sidebar(
          title = "Filtres actifs",
          open  = "always",
          width = 310,
          shiny::uiOutput(ns("sliders_dynamiques"))
        ),

        # ── Tableau compagnies ─────────────────────────────────────────────
        bslib::card(
          fill = TRUE,
          bslib::card_header(
            class = "d-flex justify-content-between align-items-center",
            shiny::tags$b("Compagnies retenues"),
            shiny::tags$div(
              class = "d-flex align-items-center gap-2",
              shiny::textOutput(ns("n_filtrees5"), inline = TRUE),
              shiny::selectInput(ns("preset"), label = NULL,
                                 choices  = c("Pr\u00e9r\u00e9glage..." = "",
                                              names(.presets_defs3)),
                                 selected = "", width = "150px")
            )
          ),
          bslib::card_body(
            style = "overflow-y:auto; padding:0.5rem;",
            shiny::uiOutput(ns("table_filtrees5"))
          )
        )
      )
    )
  )
}

# ── UI 2 — Onglet Détail compagnie ───────────────────────────────────────────

#' Onglet Détail compagnie du module analyse boursière v5
#'
#' Layout CSS grid deux sections sans scroll.
#'
#' @param id Identifiant du module
#' @return `bslib::nav_panel`
#' @importFrom shiny NS tags tagList selectInput uiOutput plotOutput
#' @importFrom bslib nav_panel card card_header card_body
#' @importFrom bsicons bs_icon
#' @export
mod_finance5_ui2 <- function(id) {
  ns <- shiny::NS(id)

  bslib::nav_panel(
    title    = "D\u00e9tail compagnie",
    fillable = TRUE,
    icon     = bsicons::bs_icon("building"),

    shiny::tags$div(
      style = paste0(
        "display: flex; flex-direction: column; ",
        "height: calc(100vh - 130px); ",
        "gap: 0.4rem; overflow: hidden; padding: 0.25rem 0;"
      ),

      # ── Barre sélecteur + info ──────────────────────────────────────────
      shiny::tags$div(
        style = "flex: 0 0 auto;",
        shiny::tags$div(
          class = "d-flex align-items-center gap-3 flex-wrap",
          shiny::tags$div(
            style = "min-width: 280px; flex: 1;",
            shiny::selectInput(ns("symbol"), NULL,
                               choices = NULL, width = "100%")
          ),
          shiny::uiOutput(ns("info_bar5"))
        )
      ),

      # ── Conteneur deux sections ─────────────────────────────────────────
      shiny::tags$div(
        style = "flex: 1; min-height: 0; display: flex; flex-direction: column; gap: 0.5rem;",

        # ─── Libellé section TOP ───────────────────────────────────────────
        shiny::tags$div(
          style = "flex: 0 0 auto; padding: 0 0.125rem;",
          shiny::tags$small(
            shiny::tags$span(
              style = "color: #6c757d; font-weight: 600; letter-spacing: 0.06em; font-size: 0.7rem;",
              "\u25b8 QUALIT\u00c9"
            )
          )
        ),

        # ─── Section TOP : 3 cartes ────────────────────────────────────────
        shiny::tags$div(
          style = paste0(
            "flex: 1; min-height: 0; ",
            "display: grid; grid-template-columns: 4fr 5fr 3fr; gap: 0.5rem;"
          ),

          # TOP-GAUCHE : Marges
          bslib::card(
            style = "height: 100%; margin: 0; min-height: 0;",
            fill  = TRUE,
            bslib::card_header(
              class = "d-flex justify-content-between align-items-center py-1",
              shiny::tags$b("Qualit\u00e9 \u2014 Marges"),
              shiny::tags$small(class = "text-muted",
                                shiny::textOutput(ns("secteur_detail5"), inline = TRUE))
            ),
            bslib::card_body(
              style = "overflow-y: auto; padding: 0.4rem; height: 100%;",
              shiny::uiOutput(ns("tableau_marges5"))
            )
          ),

          # TOP-CENTRE : ROA/ROE historique + Croissance
          bslib::card(
            style = "height: 100%; margin: 0; min-height: 0;",
            fill  = TRUE,
            bslib::card_header(
              class = "py-1",
              shiny::tags$b("Croissance \u2014 Co. vs Secteur vs Industrie")
            ),
            bslib::card_body(
              style = "overflow-y: auto; padding: 0.4rem; height: 100%;",
              shiny::uiOutput(ns("tableau_roa_roe5")),
              shiny::tags$hr(class = "my-1"),
              shiny::uiOutput(ns("tableau_croissance5"))
            )
          ),

          # TOP-DROITE : Structure financière
          bslib::card(
            style = "height: 100%; margin: 0; min-height: 0;",
            fill  = TRUE,
            bslib::card_header(
              class = "py-1",
              shiny::tags$b("Structure financi\u00e8re")
            ),
            bslib::card_body(
              style = "overflow-y: auto; padding: 0.4rem; height: 100%;",
              shiny::uiOutput(ns("tableau_structure5"))
            )
          )
        ),

        # ─── Libellé section BOTTOM ────────────────────────────────────────
        shiny::tags$div(
          style = "flex: 0 0 auto; padding: 0 0.125rem;",
          shiny::tags$small(
            shiny::tags$span(
              style = "color: #6c757d; font-weight: 600; letter-spacing: 0.06em; font-size: 0.7rem;",
              "\u25b8 PRIX & INT\u00c9R\u00caT"
            )
          )
        ),

        # ─── Section BOTTOM : 3 cartes ─────────────────────────────────────
        shiny::tags$div(
          style = paste0(
            "flex: 1; min-height: 0; ",
            "display: grid; grid-template-columns: 4fr 5fr 3fr; gap: 0.5rem;"
          ),

          # BOTTOM-GAUCHE : Valorisation
          bslib::card(
            style = "height: 100%; margin: 0; min-height: 0;",
            fill  = TRUE,
            bslib::card_header(
              class = "d-flex justify-content-between align-items-center py-1",
              shiny::tags$b("Valorisation"),
              shiny::tags$small(class = "text-muted",
                                shiny::textOutput(ns("secteur_val5"), inline = TRUE))
            ),
            bslib::card_body(
              style = "overflow-y: auto; padding: 0.4rem; height: 100%;",
              shiny::uiOutput(ns("tableau_valorisation5"))
            )
          ),

          # BOTTOM-CENTRE : Graphique + boîtes profit
          bslib::card(
            style = "height: 100%; margin: 0; min-height: 0;",
            fill  = TRUE,
            bslib::card_header(
              class = "py-1",
              shiny::tags$b("Bon moment pour acheter ?")
            ),
            bslib::card_body(
              style = paste0(
                "position: relative; padding: 0.4rem; ",
                "display: flex; flex-direction: column; ",
                "overflow: hidden; height: 100%;"
              ),
              # Sélecteur durée — superposé en haut à gauche du graphique
              shiny::tags$div(
                style = paste0(
                  "position: absolute; top: 0.25rem; left: 0.4rem; ",
                  "z-index: 10; width: 105px;"
                ),
                shiny::selectInput(
                  ns("duree_graph5"), NULL,
                  choices  = c("1 an" = 1, "3 ans" = 3, "5 ans" = 5, "10 ans" = 10),
                  selected = 1, width = "105px"
                )
              ),
              # Graphique (remplit l'espace disponible)
              shiny::tags$div(
                style = "flex: 1; min-height: 0;",
                shiny::plotOutput(ns("graph_buy5"), height = "100%")
              ),
              # Boîtes profit en bas
              shiny::uiOutput(ns("buy_signal_ui5"))
            )
          ),

          # BOTTOM-DROITE : Dividendes
          bslib::card(
            style = "height: 100%; margin: 0; min-height: 0;",
            fill  = TRUE,
            bslib::card_header(
              class = "py-1",
              shiny::tags$b("Dividendes")
            ),
            bslib::card_body(
              style = "overflow-y: auto; padding: 0.4rem; height: 100%;",
              shiny::uiOutput(ns("tableau_dividendes5"))
            )
          )
        )
      )
    )
  )
}

# ── UI complète ───────────────────────────────────────────────────────────────

#' UI complète du module analyse boursière v5
#'
#' @param id Identifiant du module
#' @return `bslib::navset_bar`
#' @importFrom bslib navset_bar
#' @export
mod_finance5_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::navset_bar(
    id = ns("main_nav"),
    mod_finance5_ui1(id),
    mod_finance5_ui2(id)
  )
}

# ── Server ────────────────────────────────────────────────────────────────────

#' Serveur du module analyse boursière v5
#'
#' @param id  Identifiant du module
#' @param con Connexion DBI active (PostgreSQL)
#'
#' @importFrom shiny moduleServer reactive req observe observeEvent renderText
#'   renderUI renderPlot updateSelectInput updateCheckboxGroupInput
#'   updateSliderInput updateCheckboxInput isolate
#' @importFrom dplyr tbl collect select filter mutate arrange group_by summarise
#'   across all_of any_of desc slice_tail left_join starts_with if_else
#' @importFrom DBI dbReadTable dbGetQuery
#' @importFrom scales dollar percent
#' @importFrom lubridate years
#' @importFrom ggplot2 ggplot aes geom_ribbon geom_line scale_y_continuous
#'   labs theme_minimal theme element_blank margin
#' @importFrom tidyr drop_na
#'
#' @export
mod_finance5_server <- function(id, con) {
  shiny::moduleServer(id, function(input, output, session) {

    # =========================================================================
    # Chargement des données
    # =========================================================================

    message("  [1/5] quality_build...")
    quality <- DBI::dbReadTable(con, DBI::Id(schema = "stocktools", table = "quality_build")) |>
      dplyr::mutate(
        date_stmts = as.Date(date_stmts),
        filingdate = as.Date(filingdate)
      )

    message("  [2/5] dividendes_build...")
    div_build <- DBI::dbReadTable(con, DBI::Id(schema = "stocktools", table = "dividendes_build")) |>
      dplyr::mutate(
        last_div_date       = as.Date(last_div_date),
        last_special_date   = as.Date(last_special_date),
        last_irregular_date = as.Date(last_irregular_date)
      )

    message("  [3/5] cagr_stmts_build + cagr_price_build...")
    cagr_stmts <- DBI::dbReadTable(con, DBI::Id(schema = "stocktools", table = "cagr_stmts_build")) |>
      dplyr::select(symbol, dplyr::starts_with("cagr_"))

    cagr_price <- DBI::dbReadTable(con, DBI::Id(schema = "stocktools", table = "cagr_price_build")) |>
      dplyr::select(symbol, cagr_1y, cagr_3y, cagr_5y) |>
      dplyr::mutate(cagr_10y = NA_real_)

    message("  [4/5] profils...")
    profile_data <- dplyr::tbl(con, dbplyr::in_schema("stocktools", "cies_profile_build")) |>
      dplyr::select(symbol, companyname) |>
      dplyr::collect()

    message("  [5/5] Jointure base_data5...")
    base_data5 <- quality |>
      dplyr::left_join(profile_data, by = "symbol") |>
      dplyr::left_join(
        dplyr::select(div_build, symbol,
                      div_ttm, div_forward, yield,
                      dplyr::starts_with("cagr_div"),
                      has_special, has_irregular,
                      last_special_date, last_irregular_date,
                      last_div_date, croissance_reguliere,
                      fcf_payout, fcf_coverage),
        by = "symbol") |>
      dplyr::left_join(cagr_stmts, by = "symbol") |>
      dplyr::left_join(cagr_price,  by = "symbol")

    # ── Médianes sectorielles ─────────────────────────────────────────────
    cols_med5 <- c("roa", "roe", "roa_moy5", "roe_moy5",
                   "m_brut", "m_ebitda", "m_net", "fcf_rev",
                   "ratio_courant", "d_actif", "couv_interet",
                   "p_to_s_calc", "p_to_ebd_calc", "pe_calc", "peg_calc",
                   "pppi")

    secteur_med5 <- base_data5 |>
      dplyr::group_by(sector) |>
      dplyr::summarise(
        dplyr::across(dplyr::all_of(cols_med5),
                      ~ stats::median(.x, na.rm = TRUE)),
        .groups = "drop"
      )

    cagr_cols_med5 <- c("cagr_1_is_revenue", "cagr_1_is_ebitda",
                        "cagr_1_is_epsdiluted", "cagr_1_cf_freecashflow")

    secteur_cagr_med5 <- base_data5 |>
      dplyr::group_by(sector) |>
      dplyr::summarise(
        dplyr::across(dplyr::any_of(cagr_cols_med5),
                      ~ stats::median(.x, na.rm = TRUE)),
        .groups = "drop"
      )

    industrie_cagr_med5 <- base_data5 |>
      dplyr::group_by(industry) |>
      dplyr::summarise(
        dplyr::across(dplyr::any_of(cagr_cols_med5),
                      ~ stats::median(.x, na.rm = TRUE)),
        .groups = "drop"
      )

    # =========================================================================
    # Préréglages
    # =========================================================================

    shiny::observeEvent(input$preset, {
      shiny::req(nchar(input$preset) > 0)
      p <- .presets_defs3[[input$preset]]

      defs_static <- Filter(function(d) !isTRUE(d$div_sub), .filter_defs2)
      cats_static <- unique(sapply(defs_static, `[[`, "cat"))
      for (cat in cats_static) {
        cat_id   <- paste0("cat_", gsub("[^a-z]", "_", tolower(cat)))
        defs_cat <- Filter(function(d) d$cat == cat, defs_static)
        ids_cat  <- sapply(defs_cat, `[[`, "id")
        shiny::updateCheckboxGroupInput(session, cat_id,
                                        selected = intersect(p$actifs, ids_cat))
      }

      shiny::updateCheckboxInput(session, "avec_div",
                                  value = "avec_div" %in% p$actifs)

      session$onFlushed(once = TRUE, function() {
        div_ids <- sapply(Filter(function(d) isTRUE(d$div_sub), .filter_defs2), `[[`, "id")
        shiny::updateCheckboxGroupInput(session, "cat_dividendes",
                                        selected = intersect(p$actifs, div_ids))
        for (fid in names(p$valeurs)) {
          shiny::updateSliderInput(session, paste0("f_", fid),
                                   value = p$valeurs[[fid]])
        }
      })
    }, ignoreInit = TRUE)

    # =========================================================================
    # Filtre secteur
    # =========================================================================

    secteurs <- c("Tous", sort(unique(stats::na.omit(base_data5$sector))))
    shiny::observeEvent(input$secteur_f, {
      shiny::updateSelectInput(session, "secteur_f",
                               choices  = secteurs,
                               selected = "Tous")
    }, once = TRUE, ignoreNULL = TRUE, ignoreInit = FALSE)

    # =========================================================================
    # Filtres actifs
    # =========================================================================

    output$div_checkbox_ui <- shiny::renderUI({
      if (!isTRUE(input$avec_div)) return(NULL)
      defs_div <- Filter(function(d) isTRUE(d$div_sub), .filter_defs2)
      ids      <- sapply(defs_div, `[[`, "id")
      labels   <- stats::setNames(ids, sapply(defs_div, `[[`, "label"))
      shiny::tagList(
        shiny::tags$p(class = "mb-0 mt-1",
                      shiny::tags$small(shiny::tags$b(shiny::tags$em("Dividendes")))),
        shiny::checkboxGroupInput(
          session$ns("cat_dividendes"),
          label    = NULL,
          choices  = labels,
          selected = character(0)
        )
      )
    })

    filtres_actifs5 <- shiny::reactive({
      defs_static <- Filter(function(d) !isTRUE(d$div_sub), .filter_defs2)
      cats_static <- unique(sapply(defs_static, `[[`, "cat"))
      checked_static <- lapply(cats_static, function(cat) {
        input[[paste0("cat_", gsub("[^a-z]", "_", tolower(cat)))]]
      })
      base_actifs <- unlist(Filter(Negate(is.null), checked_static))
      div_actifs  <- if (isTRUE(input$avec_div)) input$cat_dividendes else character(0)
      c(base_actifs, div_actifs)
    })

    # isolate() : évite boucle infinie lors de l'application d'un préréglage
    output$sliders_dynamiques <- shiny::renderUI({
      actifs <- filtres_actifs5()
      valeurs_courantes <- shiny::isolate(
        stats::setNames(
          lapply(.filter_defs2, function(d) input[[paste0("f_", d$id)]]),
          sapply(.filter_defs2, `[[`, "id")
        )
      )
      .build_sliders_actifs2(ns = session$ns, defs = .filter_defs2,
                             actifs = actifs, valeurs_courantes = valeurs_courantes)
    })

    # =========================================================================
    # Filtrage réactif
    # =========================================================================

    df_filtres5 <- shiny::reactive({
      df     <- base_data5
      actifs <- filtres_actifs5()

      if (!is.null(input$secteur_f) && input$secteur_f != "Tous")
        df <- df |> dplyr::filter(sector == input$secteur_f)

      if (isTRUE(input$avec_div))
        df <- df[!is.na(df$div_ttm) & df$div_ttm > 0, ]

      for (d in .filter_defs2) {
        if (!d$id %in% actifs) next
        val <- input[[paste0("f_", d$id)]]
        if (is.null(val)) next
        seuil_val <- if (d$fmt == "pct") val / 100 else val
        col_vals  <- df[[d$col]]
        if (d$seuil == "min") {
          df <- df[!is.na(col_vals) & col_vals >= seuil_val, ]
        } else if (isTRUE(d$no_negative)) {
          df <- df[!is.na(col_vals) & col_vals >= 0 & col_vals <= seuil_val, ]
        } else {
          df <- df[is.na(col_vals) | col_vals <= seuil_val, ]
        }
      }
      df
    })

    # =========================================================================
    # Onglet Filtres — outputs
    # =========================================================================

    output$n_filtrees5 <- shiny::renderText({
      paste0(nrow(df_filtres5()), " compagnies")
    })

    output$table_filtrees5 <- shiny::renderUI({
      df <- df_filtres5() |> dplyr::arrange(ratio_moyen)
      if (nrow(df) == 0)
        return(shiny::tags$p(class = "text-muted fst-italic small px-2 pt-2",
                             "Aucune compagnie ne correspond aux filtres."))

      fmt_cap <- function(x) {
        if (is.na(x)) return("N/D")
        if (x >= 200000) paste0(round(x / 1000, 1), " T")
        else if (x >= 2000) paste0(round(x / 1000, 1), " G")
        else paste0(round(x), " M")
      }

      shiny::tags$table(
        class = "table table-sm table-hover table-striped mb-0",
        shiny::tags$thead(shiny::tags$tr(
          shiny::tags$th("Ticker"),
          shiny::tags$th("Compagnie"),
          shiny::tags$th("Secteur"),
          shiny::tags$th(class = "text-end", "Mkt Cap"),
          shiny::tags$th(class = "text-end", "Yield")
        )),
        shiny::tags$tbody(
          lapply(seq_len(nrow(df)), function(i) {
            row     <- df[i, ]
            onclick <- sprintf(
              "Shiny.setInputValue('%s', '%s', {priority: 'event'})",
              session$ns("clicked_symbol"), row$symbol
            )
            shiny::tags$tr(
              style   = "cursor:pointer;",
              onclick = onclick,
              shiny::tags$td(shiny::tags$b(row$symbol)),
              shiny::tags$td(row$companyname),
              shiny::tags$td(row$sector),
              shiny::tags$td(class = "text-end", fmt_cap(row$mktcap_m)),
              shiny::tags$td(class = "text-end",
                             if (is.na(row$yield)) "N/D"
                             else scales::percent(row$yield, accuracy = 0.1))
            )
          })
        )
      )
    })

    # Clic sur une ligne → naviguer vers Détail compagnie
    shiny::observeEvent(input$clicked_symbol, {
      shiny::req(nchar(input$clicked_symbol) > 0)
      shiny::updateSelectInput(session, "symbol",
                               selected = input$clicked_symbol)
      bslib::nav_select("main_nav", "D\u00e9tail compagnie", session = session)
    })

    # Sync sélecteur symbole
    shiny::observe({
      df <- df_filtres5() |> dplyr::arrange(symbol)
      if (nrow(df) == 0) {
        shiny::updateSelectInput(session, "symbol",
                                 choices = c("Aucune compagnie" = ""))
        return()
      }
      choices <- stats::setNames(df$symbol,
                                 paste0(df$symbol, " \u2014 ", df$companyname))
      shiny::updateSelectInput(session, "symbol",
                               choices  = choices,
                               selected = choices[1])
    })

    # =========================================================================
    # Données réactives — symbole sélectionné
    # =========================================================================

    donnees_symbol5 <- shiny::reactive({
      shiny::req(input$symbol, nchar(input$symbol) > 0)
      base_data5 |> dplyr::filter(symbol == input$symbol)
    })

    val_hist5 <- shiny::reactive({
      shiny::req(input$symbol, nchar(input$symbol) > 0)
      dplyr::tbl(con, dbplyr::in_schema("stocktools", "valuation_build")) |>
        dplyr::filter(symbol == !!input$symbol) |>
        dplyr::collect() |>
        dplyr::mutate(date = as.Date(date)) |>
        dplyr::arrange(date)
    })

    val_hist5_filtered <- shiny::reactive({
      n_years <- as.numeric(shiny::req(input$duree_graph5))
      val_hist5() |>
        dplyr::filter(date >= Sys.Date() - lubridate::years(n_years))
    })

    val_latest5 <- shiny::reactive({
      df <- val_hist5()
      if (nrow(df) == 0) return(NULL)
      df |> dplyr::arrange(date) |> dplyr::slice_tail(n = 1)
    })

    # =========================================================================
    # Barre d'info compagnie
    # =========================================================================

    output$info_bar5 <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol5()) > 0)
      d       <- donnees_symbol5()
      cagr_1y <- d$cagr_1y
      close   <- d$close
      chg_usd <- if (!is.na(cagr_1y) && !is.na(close))
        close - close / (1 + cagr_1y) else NA
      couleur <- if (is.na(cagr_1y)) "secondary"
                 else if (cagr_1y >= 0) "success" else "danger"
      txt_chg <- if (is.na(cagr_1y)) "N/D"
                 else sprintf("%+.2f$ (%+.1f%% \u00b7 1 an)", chg_usd, cagr_1y * 100)

      periode_txt <- if (!is.na(d$period) && !is.na(d$date_stmts))
        paste0(d$period, " \u00b7 ", format(d$date_stmts, "%Y-%m-%d")) else "\u2014"
      depot_txt <- if (!is.na(d$filingdate))
        paste0("Disponible : ", format(d$filingdate, "%Y-%m-%d")) else ""

      shiny::tags$div(
        class = "d-flex align-items-center gap-3 flex-wrap",
        shiny::tags$span(class = "badge bg-secondary", periode_txt),
        if (nchar(depot_txt) > 0)
          shiny::tags$span(class = "text-muted small", depot_txt),
        shiny::tags$span(class = "fs-5 fw-bold",
                         scales::dollar(close, accuracy = 0.01)),
        shiny::tags$span(class = paste0("fw-semibold text-", couleur), txt_chg)
      )
    })

    # =========================================================================
    # Tableau Marges (TOP-GAUCHE)
    # =========================================================================

    output$secteur_detail5 <- shiny::renderText({
      shiny::req(nrow(donnees_symbol5()) > 0)
      sec <- donnees_symbol5()$sector
      if (is.na(sec)) return("")
      paste("vs.", sec)
    })

    output$tableau_marges5 <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol5()) > 0)
      d   <- donnees_symbol5()
      sec <- d$sector
      ref <- secteur_med5 |> dplyr::filter(sector == sec)
      r   <- if (nrow(ref) == 1) ref else
        as.data.frame(as.list(stats::setNames(
          rep(NA_real_, length(cols_med5)), cols_med5)))

      shiny::tags$table(
        class = "table table-sm table-hover mb-0",
        shiny::tags$thead(shiny::tags$tr(
          shiny::tags$th("Marge"),
          shiny::tags$th(class = "text-end", "Cie"),
          shiny::tags$th(class = "text-end text-muted", "Secteur"),
          shiny::tags$th(class = "text-center", "")
        )),
        shiny::tags$tbody(
          .lq2("Marge brute",  .fmt_pct2(d$m_brut),  .fmt_pct2(r$m_brut),
               .sig2(d$m_brut,  r$m_brut)),
          .lq2("Marge EBITDA", .fmt_pct2(d$m_ebitda), .fmt_pct2(r$m_ebitda),
               .sig2(d$m_ebitda, r$m_ebitda)),
          .lq2("Marge nette",  .fmt_pct2(d$m_net),   .fmt_pct2(r$m_net),
               .sig2(d$m_net,   r$m_net)),
          .lq2("Marge FCF",    .fmt_pct2(d$fcf_rev), .fmt_pct2(r$fcf_rev),
               .sig2(d$fcf_rev, r$fcf_rev))
        )
      )
    })

    # =========================================================================
    # Tableau ROA/ROE historique (TOP-CENTRE, en haut)
    # =========================================================================

    output$tableau_roa_roe5 <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol5()) > 0)
      d   <- donnees_symbol5()
      sec <- d$sector
      ref <- secteur_med5 |> dplyr::filter(sector == sec)
      r   <- if (nrow(ref) == 1) ref else
        as.data.frame(as.list(stats::setNames(
          rep(NA_real_, length(cols_med5)), cols_med5)))

      # Coloration : cie vs secteur (même période)
      td_val <- function(val, ref_val, inverse = FALSE) {
        sig <- .sig2(val, ref_val, inverse = inverse)
        bg  <- switch(sig,
          vert  = "rgba(25,135,84,0.18)",
          rouge = "rgba(220,53,69,0.18)",
          jaune = "rgba(255,193,7,0.18)",
          "transparent"
        )
        shiny::tags$td(
          class = "text-end fw-semibold small",
          style = paste0("background:", bg, ";"),
          .fmt_pct2(val)
        )
      }

      td_dash <- function()
        shiny::tags$td(class = "text-end text-muted small", "\u2014")

      shiny::tags$table(
        class = "table table-sm table-hover mb-0",
        shiny::tags$thead(shiny::tags$tr(
          shiny::tags$th("Ratio"),
          shiny::tags$th(class = "text-end small", "1a"),
          shiny::tags$th(class = "text-end small text-muted", "3a"),
          shiny::tags$th(class = "text-end small", "5a"),
          shiny::tags$th(class = "text-end small text-muted", "10a"),
          shiny::tags$th(class = "text-end small text-muted", "Sect.")
        )),
        shiny::tags$tbody(
          shiny::tags$tr(
            shiny::tags$td(class = "small", "ROA"),
            td_val(d$roa,     r$roa),
            td_dash(),
            td_val(d$roa_moy5, r$roa_moy5),
            td_dash(),
            shiny::tags$td(class = "text-end text-muted small", .fmt_pct2(r$roa))
          ),
          shiny::tags$tr(
            shiny::tags$td(class = "small", "ROE"),
            td_val(d$roe,     r$roe),
            td_dash(),
            td_val(d$roe_moy5, r$roe_moy5),
            td_dash(),
            shiny::tags$td(class = "text-end text-muted small", .fmt_pct2(r$roe))
          )
        )
      )
    })

    # =========================================================================
    # Tableau Croissance (TOP-CENTRE, en bas)
    # =========================================================================

    output$tableau_croissance5 <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol5()) > 0)
      d   <- donnees_symbol5()
      sec <- d$sector
      ind <- d$industry

      s_med <- secteur_cagr_med5   |> dplyr::filter(sector   == sec)
      i_med <- industrie_cagr_med5 |> dplyr::filter(industry == ind)

      get_med <- function(df, col)
        if (nrow(df) == 1 && col %in% names(df)) df[[col]] else NA_real_

      px1 <- d$cagr_1y; px3 <- d$cagr_3y; px5 <- d$cagr_5y; px10 <- NA_real_

      ligne_cagr <- function(label, c1, s1, i1, c3, c5, c10) {
        shiny::tags$tr(
          shiny::tags$td(class = "small", label),
          .td_cagr3(c1, px1),
          .td_ref3(s1),
          .td_ref3(i1),
          .td_cagr3(c3, px3),
          .td_cagr3(c5, px5),
          .td_cagr3(c10, px10)
        )
      }

      ligne_prix <- function(label, c1, c3, c5, c10) {
        shiny::tags$tr(
          class = "table-light",
          shiny::tags$td(class = "small fw-semibold", label),
          .td_ref3(c1),
          shiny::tags$td(class = "text-end text-muted small", "\u2014"),
          shiny::tags$td(class = "text-end text-muted small", "\u2014"),
          .td_ref3(c3),
          .td_ref3(c5),
          .td_ref3(c10)
        )
      }

      ligne_div <- function(label, c1, c3, c5, c10) {
        shiny::tags$tr(
          shiny::tags$td(class = "small", label),
          .td_cagr3(c1,  px1),
          shiny::tags$td(class = "text-end text-muted small", "\u2014"),
          shiny::tags$td(class = "text-end text-muted small", "\u2014"),
          .td_cagr3(c3,  px3),
          .td_cagr3(c5,  px5),
          .td_cagr3(c10, px10)
        )
      }

      shiny::tags$table(
        class = "table table-sm table-hover mb-0",
        shiny::tags$thead(shiny::tags$tr(
          shiny::tags$th("M\u00e9trique"),
          shiny::tags$th(class = "text-end small", "Co. 1a"),
          shiny::tags$th(class = "text-end small text-muted", "Sect."),
          shiny::tags$th(class = "text-end small text-muted", "Ind."),
          shiny::tags$th(class = "text-end small", "3a"),
          shiny::tags$th(class = "text-end small", "5a"),
          shiny::tags$th(class = "text-end small", "10a")
        )),
        shiny::tags$tbody(
          ligne_prix("Prix",
            d$cagr_1y, d$cagr_3y, d$cagr_5y, d$cagr_10y),
          .section_qualite("Fondamentaux"),
          ligne_cagr("Sales Gr.",
            d$cagr_1_is_revenue,
            get_med(s_med, "cagr_1_is_revenue"),
            get_med(i_med, "cagr_1_is_revenue"),
            d$cagr_3_is_revenue, d$cagr_5_is_revenue, d$cagr_10_is_revenue),
          ligne_cagr("EBITDA Gr.",
            d$cagr_1_is_ebitda,
            get_med(s_med, "cagr_1_is_ebitda"),
            get_med(i_med, "cagr_1_is_ebitda"),
            d$cagr_3_is_ebitda, d$cagr_5_is_ebitda, d$cagr_10_is_ebitda),
          ligne_cagr("EPS Gr.",
            d$cagr_1_is_epsdiluted,
            get_med(s_med, "cagr_1_is_epsdiluted"),
            get_med(i_med, "cagr_1_is_epsdiluted"),
            d$cagr_3_is_epsdiluted, d$cagr_5_is_epsdiluted, d$cagr_10_is_epsdiluted),
          ligne_cagr("FCF Gr.",
            d$cagr_1_cf_freecashflow,
            get_med(s_med, "cagr_1_cf_freecashflow"),
            get_med(i_med, "cagr_1_cf_freecashflow"),
            d$cagr_3_cf_freecashflow, d$cagr_5_cf_freecashflow, d$cagr_10_cf_freecashflow),
          .section_qualite("Dividendes"),
          ligne_div("Div. Gr.",
            d$cagr_div_1a, d$cagr_div_3a, d$cagr_div_5a, d$cagr_div_10a)
        )
      )
    })

    # =========================================================================
    # Tableau Structure financière (TOP-DROITE)
    # =========================================================================

    output$tableau_structure5 <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol5()) > 0)
      d   <- donnees_symbol5()
      sec <- d$sector
      ref <- secteur_med5 |> dplyr::filter(sector == sec)
      r   <- if (nrow(ref) == 1) ref else
        as.data.frame(as.list(stats::setNames(
          rep(NA_real_, length(cols_med5)), cols_med5)))

      mktcap_cat <- if (is.na(d$mktcap_m)) "N/D"
                    else if (d$mktcap_m >= 200000) "Mega Cap"
                    else if (d$mktcap_m >=  10000) "Large Cap"
                    else if (d$mktcap_m >=   2000) "Mid Cap"
                    else "Small Cap"

      shiny::tags$table(
        class = "table table-sm table-hover mb-0",
        shiny::tags$thead(shiny::tags$tr(
          shiny::tags$th("Ratio"),
          shiny::tags$th(class = "text-end", "Cie"),
          shiny::tags$th(class = "text-end text-muted", "Secteur"),
          shiny::tags$th(class = "text-center", "")
        )),
        shiny::tags$tbody(
          .lq2("Dette / Actif",
               .fmt_pct2(d$d_actif),   .fmt_pct2(r$d_actif),
               .sig2(d$d_actif,   r$d_actif,   inverse = TRUE)),
          .lq2("PPPI",
               .fmt_pct2(d$pppi),      .fmt_pct2(r$pppi),
               .sig2(d$pppi,      r$pppi,      inverse = TRUE)),
          .lq2("Couverture int\u00e9r\u00eats",
               .fmt_x2(d$couv_interet), .fmt_x2(r$couv_interet),
               .sig2(d$couv_interet, r$couv_interet)),
          .lq2("Ratio liquidit\u00e9",
               .fmt_x2(d$ratio_courant), .fmt_x2(r$ratio_courant),
               .sig2(d$ratio_courant, r$ratio_courant)),
          shiny::tags$tr(
            shiny::tags$td("Market Cap"),
            shiny::tags$td(class = "text-end fw-semibold", colspan = 3, mktcap_cat)
          )
        )
      )
    })

    # =========================================================================
    # Tableau Valorisation (BOTTOM-GAUCHE)
    # =========================================================================

    output$secteur_val5 <- shiny::renderText({
      shiny::req(nrow(donnees_symbol5()) > 0)
      sec <- donnees_symbol5()$sector
      if (is.na(sec)) return("")
      paste("vs.", sec)
    })

    output$tableau_valorisation5 <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol5()) > 0)
      d   <- donnees_symbol5()
      sec <- d$sector
      ref <- secteur_med5 |> dplyr::filter(sector == sec)
      r   <- if (nrow(ref) == 1) ref else
        as.data.frame(as.list(stats::setNames(
          rep(NA_real_, length(cols_med5)), cols_med5)))

      shiny::tags$table(
        class = "table table-sm table-hover mb-0",
        shiny::tags$thead(shiny::tags$tr(
          shiny::tags$th("Ratio"),
          shiny::tags$th(class = "text-end", "Cie"),
          shiny::tags$th(class = "text-end text-muted", "Secteur"),
          shiny::tags$th(class = "text-center", "")
        )),
        shiny::tags$tbody(
          .lq2("P/E",
               .fmt_x2(d$pe_calc),      .fmt_x2(r$pe_calc),
               .sig2(d$pe_calc,      r$pe_calc,      inverse = TRUE)),
          .lq2("PEG",
               .fmt_num2(d$peg_calc),   .fmt_num2(r$peg_calc),
               .sig2(d$peg_calc,     r$peg_calc,     inverse = TRUE)),
          .lq2("P/S",
               .fmt_x2(d$p_to_s_calc),  .fmt_x2(r$p_to_s_calc),
               .sig2(d$p_to_s_calc,  r$p_to_s_calc,  inverse = TRUE)),
          .lq2("P/EBITDA",
               .fmt_x2(d$p_to_ebd_calc), .fmt_x2(r$p_to_ebd_calc),
               .sig2(d$p_to_ebd_calc, r$p_to_ebd_calc, inverse = TRUE))
        )
      )
    })

    # =========================================================================
    # Graphique bandes buy/sell (BOTTOM-CENTRE)
    # =========================================================================

    output$graph_buy5 <- shiny::renderPlot({
      df  <- val_hist5_filtered()
      met <- if (is.null(input$metrique_graph5) ||
                 !input$metrique_graph5 %in% names(.metric_val_cols3))
               "P/S" else input$metrique_graph5
      cols <- .metric_val_cols3[[met]]
      if (is.null(cols) || nrow(df) == 0) return(NULL)

      df_plot <- df |>
        dplyr::select(date, close,
                      buy     = !!cols$buy,
                      caution = !!cols$caution,
                      sell    = !!cols$sell) |>
        tidyr::drop_na(buy, sell)

      if (nrow(df_plot) == 0) return(NULL)

      ggplot2::ggplot(df_plot, ggplot2::aes(x = date)) +
        ggplot2::geom_ribbon(ggplot2::aes(ymin = buy, ymax = caution),
                             fill = "#198754", alpha = 0.15) +
        ggplot2::geom_ribbon(ggplot2::aes(ymin = caution, ymax = sell),
                             fill = "#ffc107", alpha = 0.15) +
        ggplot2::geom_line(ggplot2::aes(y = buy),
                           colour = "#198754", linewidth = 0.7) +
        ggplot2::geom_line(ggplot2::aes(y = caution),
                           colour = "#ffc107", linewidth = 0.7) +
        ggplot2::geom_line(ggplot2::aes(y = sell),
                           colour = "#dc3545", linewidth = 0.7) +
        ggplot2::geom_line(ggplot2::aes(y = close),
                           colour = "black", linewidth = 1.1) +
        ggplot2::scale_y_continuous(labels = scales::dollar) +
        ggplot2::labs(x = NULL, y = NULL) +
        ggplot2::theme_minimal(base_size = 10) +
        ggplot2::theme(panel.grid.minor = ggplot2::element_blank(),
                       plot.margin      = ggplot2::margin(4, 4, 4, 4))
    }, bg = "transparent")

    # =========================================================================
    # Boîtes profit (BOTTOM-CENTRE, sous le graphique)
    # =========================================================================

    output$buy_signal_ui5 <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol5()) > 0)
      d  <- donnees_symbol5()
      vl <- val_latest5()

      met_actif <- if (is.null(input$metrique_graph5) ||
                       !input$metrique_graph5 %in% names(.metric_val_cols3))
                     "P/S" else input$metrique_graph5

      calc_profit <- function(caution_col) {
        if (is.null(vl) || nrow(vl) == 0) return(NA_real_)
        cl <- vl$close; ca <- vl[[caution_col]]
        if (anyNA(c(cl, ca)) || cl <= 0) return(NA_real_)
        (ca - cl) / cl
      }

      boites <- list(
        list(label = "Profit P/S",      met = "P/S",      profit = calc_profit("caution_p_to_s")),
        list(label = "Profit P/EBITDA", met = "P/EBITDA",  profit = calc_profit("caution_p_to_ebitda")),
        list(label = "Profit P/E",      met = "P/E",       profit = calc_profit("caution_pe")),
        list(label = "Profit P/E dil.", met = "P/E dil.",  profit = calc_profit("caution_pe_dil"))
      )

      boite_profit <- function(b) {
        val     <- b$profit
        actif   <- isTRUE(b$met == met_actif)
        couleur <- if (is.na(val) || is.nan(val)) "secondary"
                   else if (val >= 0.10) "success"
                   else if (val >= 0)    "warning"
                   else                  "danger"
        txt <- if (is.na(val) || is.nan(val)) "N/D"
               else scales::percent(val, accuracy = 0.1)
        border_cls  <- if (actif) "border border-3" else "border"
        opacity_cls <- if (actif) "bg-opacity-25"   else "bg-opacity-10"
        onclick_js  <- sprintf(
          "Shiny.setInputValue('%s', '%s', {priority: 'event'})",
          session$ns("metrique_graph5"), b$met
        )
        shiny::tags$div(
          class   = paste0("text-center p-1 rounded ", border_cls, " border-", couleur,
                           " bg-", couleur, " ", opacity_cls, " flex-fill"),
          style   = "cursor:pointer; user-select:none;",
          onclick = onclick_js,
          shiny::tags$div(class = "small fw-semibold", b$label),
          shiny::tags$div(class = paste0("fs-6 fw-bold text-", couleur), txt)
        )
      }

      rdt_gordon <- if (!anyNA(c(d$yield, d$cagr_div_5a)))
                      d$yield + d$cagr_div_5a else NA_real_
      couleur_gordon <- if (is.na(rdt_gordon)) "secondary"
                        else if (rdt_gordon >= 0.10) "success"
                        else if (rdt_gordon >= 0.06) "warning"
                        else "danger"
      txt_gordon <- if (is.na(rdt_gordon)) "N/D"
                    else scales::percent(rdt_gordon, accuracy = 0.1)

      shiny::tags$div(
        class = "d-flex gap-1 mt-1 flex-wrap",
        lapply(boites, boite_profit),
        shiny::tags$div(
          class = paste0("text-center p-1 rounded border border-", couleur_gordon,
                         " bg-", couleur_gordon, " bg-opacity-10 flex-fill"),
          shiny::tags$div(class = "small fw-semibold", "Gordon"),
          shiny::tags$div(class = paste0("fs-6 fw-bold text-", couleur_gordon),
                          txt_gordon)
        )
      )
    })

    # =========================================================================
    # Tableau Dividendes (BOTTOM-DROITE)
    # =========================================================================

    output$tableau_dividendes5 <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol5()) > 0)
      d <- donnees_symbol5()

      flag_special   <- if (isTRUE(d$has_special))
        paste0("Oui (", format(d$last_special_date, "%Y-%m-%d"), ")") else "Non"
      flag_irregular <- if (isTRUE(d$has_irregular))
        paste0("Oui (", format(d$last_irregular_date, "%Y-%m-%d"), ")") else "Non"

      txt_fcf_pay <- if (is.na(d$fcf_payout)) "N/D"
                     else scales::percent(d$fcf_payout, accuracy = 0.1)
      txt_fcf_cov <- .fmt_x2(d$fcf_coverage)

      lignes <- list(
        list("Yield estim\u00e9",             .fmt_pct2(d$yield, 0.1)),
        list("Croissance r\u00e9guli\u00e8re", if (isTRUE(d$croissance_reguliere)) "Oui" else "Non"),
        list("FCF Payout",                 txt_fcf_pay),
        list("FCF Coverage",               txt_fcf_cov),
        list("Dividende sp\u00e9cial",     flag_special),
        list("Div. irr\u00e9gulier",       flag_irregular)
      )

      shiny::tags$table(
        class = "table table-sm mb-0",
        shiny::tags$tbody(lapply(lignes, function(l) {
          shiny::tags$tr(
            shiny::tags$td(l[[1]]),
            shiny::tags$td(class = "text-end fw-semibold", l[[2]])
          )
        }))
      )
    })

  })
}
