# =============================================================================
# mod_finance4.R — Module Shiny : analyse boursière S&P 500 (version 4)
#
# Module autonome (helpers intégrés, plus de dépendance vers mod_finance3.R).
#
# Sources de données : quality_build, dividendes_build,
#   cagr_stmts_build, cagr_price_build, valuation_build (graphique)
#
# Fonctions exportées :
#   mod_finance4_ui1(id)         — nav_panel "Filtres"
#   mod_finance4_ui2(id)         — nav_panel "Détail compagnie"
#   mod_finance4_ui(id)          — navset_bar wrapper
#   mod_finance4_server(id, con) — logique serveur
# =============================================================================

# ── Helpers — tableaux qualité ────────────────────────────────────────────────

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
        style = paste0("color:", cl$couleur, "; font-size:1.1rem;"), "\u25cf"
      )
    )
  )
}

.section_qualite <- function(label) {
  shiny::tags$tr(
    shiny::tags$td(
      colspan = 4, class = "pt-2 pb-0",
      shiny::tags$small(shiny::tags$b(shiny::tags$em(label)))
    )
  )
}

# ── Helpers — filtres ─────────────────────────────────────────────────────────

# Définitions des filtres
# fmt         : "pct" → slider 0-N, filtre /100 | "dec" → décimal | "num" → brut
# seuil       : "min" → cie >= valeur | "max" → cie <= valeur
# type        : absent = slider | "binary" = checkbox (pas de slider)
# no_negative : TRUE → exclut aussi les valeurs négatives (filtre "max" uniquement)
# default     : TRUE = coché au démarrage
.filter_defs2 <- list(
  list(id="roa",      label="ROA",              cat="Rentabilité", col="roa",                  min=0, max=60,   step=1,    fmt="pct", seuil="min", default=TRUE),
  list(id="roe",      label="ROE",              cat="Rentabilité", col="roe",                  min=0, max=60,   step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="m_brut",   label="Marge brute",      cat="Rentabilité", col="m_brut",               min=0, max=100,  step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="m_ebitda", label="Marge EBITDA",     cat="Rentabilité", col="m_ebitda",             min=0, max=60,   step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="m_net",    label="Marge nette",      cat="Rentabilité", col="m_net",                min=0, max=50,   step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="cagr_rev", label="Sales Growth 3a",  cat="Croissance",  col="cagr_3_is_revenue",    min=0, max=50,   step=1,    fmt="pct", seuil="min", default=TRUE),
  list(id="cagr_ebd", label="EBITDA Growth 3a", cat="Croissance",  col="cagr_3_is_ebitda",     min=0, max=50,   step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="cagr_eps", label="EPS Growth 3a",    cat="Croissance",  col="cagr_3_is_epsdiluted", min=0, max=50,   step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="br_pts",   label="BR Sales",         cat="Buy Ratio",   col="r_pts",  min=0, max=1, step=0.05, fmt="dec", seuil="max", default=TRUE,  val=0.1),
  list(id="br_ebd",   label="BR EBITDA",        cat="Buy Ratio",   col="r_ebd",  min=0, max=1, step=0.05, fmt="dec", seuil="max", default=FALSE, val=0.1),
  list(id="br_pe",    label="BR EPS",           cat="Buy Ratio",   col="r_pe",   min=0, max=1, step=0.05, fmt="dec", seuil="max", default=FALSE, val=0.1),
  list(id="br_ped",   label="BR EPS dil.",      cat="Buy Ratio",   col="r_ped",  min=0, max=1, step=0.05, fmt="dec", seuil="max", default=FALSE, val=0.1),
  list(id="r_courant",label="Ratio courant",    cat="Solidité",    col="ratio_courant",        min=0, max=5,    step=0.1,  fmt="dec", seuil="min", default=FALSE),
  list(id="fcf_rev",  label="FCF / Revenus",    cat="Solidité",    col="fcf_rev",              min=0, max=50,   step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="mktcap",   label="Mkt Cap ($M)",     cat="Marché",      col="mktcap_m",             min=0, max=3000, step=50,   fmt="num", seuil="min", default=FALSE),
  list(id="yield",    label="Yield min.",       cat="Dividendes",  col="yield",      min=0, max=10,  step=0.5, fmt="pct", seuil="min", default=FALSE, val=2),
  list(id="cagr_div5",label="CAGR Div. 5a",    cat="Dividendes",  col="cagr_div_5a",min=0, max=20,  step=1,   fmt="pct", seuil="min", default=FALSE, val=3),
  # FCF Payout : exclut les payout négatifs (FCF négatif) et NA
  list(id="fcf_pay",  label="FCF Payout max.", cat="Dividendes",  col="fcf_payout", min=0, max=100, step=5,   fmt="pct", seuil="max", default=FALSE, val=80, no_negative=TRUE),
  # Filtre binaire : checkbox dans Filtres actifs (pas de slider)
  list(id="avec_div", label="With dividend",   cat="Dividendes",  col="div_ttm",    type="binary",            default=FALSE)
)

# Préréglages de filtres
.presets_defs3 <- list(
  "Croissance qualité" = list(
    actifs  = c("roa", "m_ebitda", "cagr_rev", "cagr_eps", "br_pts"),
    valeurs = list(roa = 10, m_ebitda = 15, cagr_rev = 8, cagr_eps = 8, br_pts = 0.5)
  ),
  "Dividendes stables" = list(
    actifs  = c("roa", "fcf_rev", "r_courant", "br_pts", "yield", "avec_div"),
    valeurs = list(roa = 5, fcf_rev = 8, r_courant = 1.2, br_pts = 0.7, yield = 2)
  ),
  "Valeur défensive" = list(
    actifs  = c("m_brut", "m_net", "r_courant", "br_pts", "br_ebd"),
    valeurs = list(m_brut = 30, m_net = 8, r_courant = 1.5, br_pts = 0.5, br_ebd = 0.5)
  )
)

# Checkboxes groupées par catégorie (sidebar Sélection)
.build_checkbox_ui2 <- function(ns, defs) {
  cats <- unique(sapply(defs, `[[`, "cat"))
  shiny::tagList(lapply(cats, function(cat) {
    defs_cat <- Filter(function(d) d$cat == cat, defs)
    ids      <- sapply(defs_cat, `[[`, "id")
    labels   <- stats::setNames(ids, sapply(defs_cat, `[[`, "label"))
    defaults <- ids[sapply(defs_cat, `[[`, "default")]
    shiny::tagList(
      shiny::tags$p(class = "mb-0 mt-2",
                    shiny::tags$small(shiny::tags$b(shiny::tags$em(cat)))),
      shiny::checkboxGroupInput(
        ns(paste0("cat_", gsub("[^a-z]", "_", tolower(cat)))),
        label    = NULL,
        choices  = labels,
        selected = defaults
      )
    )
  }))
}

# Sliders/checkboxes actifs (sidebar Filtres actifs)
# valeurs_courantes : liste nommée par id → valeur actuelle de l'input
#   → permet de conserver la valeur quand on ajoute/retire un filtre
.build_sliders_actifs2 <- function(ns, defs, actifs, valeurs_courantes = list()) {
  if (length(actifs) == 0) {
    return(shiny::tags$p(
      class = "text-muted small fst-italic",
      "Cochez des filtres dans la sélection."
    ))
  }
  defs_actifs <- Filter(function(d) d$id %in% actifs, defs)
  cats <- unique(sapply(defs_actifs, `[[`, "cat"))
  shiny::tagList(lapply(cats, function(cat) {
    defs_cat <- Filter(function(d) d$cat == cat, defs_actifs)
    shiny::tagList(
      shiny::tags$p(class = "mb-0 mt-1",
                    shiny::tags$small(shiny::tags$b(shiny::tags$em(cat)))),
      lapply(defs_cat, function(d) {
        cur_val <- valeurs_courantes[[d$id]]

        # ── Filtre binaire → checkbox ────────────────────────────────────────
        if (isTRUE(d$type == "binary")) {
          return(shiny::tags$div(
            class = "ms-1",
            shiny::checkboxInput(
              ns(paste0("f_", d$id)),
              label = d$label,
              value = isTRUE(cur_val)
            )
          ))
        }

        # ── Filtre slider ────────────────────────────────────────────────────
        # Priorité : valeur courante > val définie > min/max selon seuil
        val_init <- if (!is.null(cur_val)) cur_val
                    else if (!is.null(d$val)) d$val
                    else if (d$seuil == "min") d$min
                    else d$max
        post_str <- switch(d$fmt, pct = " %", num = " $M", NULL)
        shiny::tags$div(
          class = "d-flex align-items-center gap-1",
          shiny::tags$small(
            style = "min-width:72px; font-size:0.75rem; white-space:nowrap;",
            d$label
          ),
          shiny::tags$div(
            style = "flex:1; min-width:0; margin-bottom:-10px;",
            shiny::sliderInput(ns(paste0("f_", d$id)), label = NULL,
                               min = d$min, max = d$max, value = val_init,
                               step = d$step, post = post_str, width = "100%")
          )
        )
      })
    )
  }))
}

# Raccourcis affichage
.lq2 <- function(label, val_cie, val_sec, signal)
  .ligne_qualite(label, val_cie, val_sec, signal)

.sig2 <- function(val, ref, inverse = FALSE) {
  if (anyNA(c(val, ref)) || is.nan(val) || is.nan(ref) || ref == 0) return("jaune")
  r <- if (inverse) ref / val else val / ref
  if (r > 1.05) "vert" else if (r < 0.95) "rouge" else "jaune"
}

.signal_dot2 <- function(signal) {
  cfg <- list(vert = "#198754", jaune = "#856404", rouge = "#dc3545")
  shiny::tags$span(
    style = paste0("color:", cfg[[signal]], "; font-size:1.1rem;"), "\u25cf"
  )
}

.fmt_pct2 <- function(x, acc = 0.1)
  if (is.na(x) || is.nan(x)) "N/D" else scales::percent(x, accuracy = acc)
.fmt_x2 <- function(x)
  if (is.na(x) || is.nan(x)) "N/D" else paste0(round(x, 1), "\u00d7")
.fmt_num2 <- function(x, digits = 2)
  if (is.na(x) || is.nan(x)) "N/D" else formatC(x, digits = digits, format = "f")

# Signal croissance vs cours boursier
.sig_vs_prix3 <- function(metrique_cagr, prix_cagr) {
  if (anyNA(c(metrique_cagr, prix_cagr)) ||
      is.nan(metrique_cagr) || is.nan(prix_cagr)) return("neutre")
  diff <- metrique_cagr - prix_cagr
  if (diff >  0.01) "vert" else if (diff < -0.01) "rouge" else "jaune"
}

.td_cagr3 <- function(val, prix_cagr) {
  if (is.null(val) || length(val) == 0 || is.na(val) || is.nan(val))
    return(shiny::tags$td(class = "text-end text-muted small", "N/D"))
  sig <- .sig_vs_prix3(val, prix_cagr)
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

.td_ref3 <- function(val) {
  if (is.null(val) || length(val) == 0 || is.na(val) || is.nan(val))
    return(shiny::tags$td(class = "text-end text-muted small", "\u2014"))
  shiny::tags$td(class = "text-end text-muted small", .fmt_pct2(val))
}

# Mapping métrique → colonnes valuation_build
.metric_val_cols3 <- list(
  "P/S"      = list(buy = "buy_p_to_s",      sell = "sell_p_to_s",      caution = "caution_p_to_s"),
  "P/EBITDA" = list(buy = "buy_p_to_ebitda", sell = "sell_p_to_ebitda", caution = "caution_p_to_ebitda"),
  "P/E"      = list(buy = "buy_pe",           sell = "sell_pe",          caution = "caution_pe"),
  "P/E dil." = list(buy = "buy_pe_dil",       sell = "sell_pe_dil",      caution = "caution_pe_dil")
)

# ── UI 1 — Onglet Filtres ────────────────────────────────────────────────────

#' Onglet Filtres du module analyse boursière v4
#'
#' @param id Identifiant du module
#' @return `bslib::nav_panel`
#' @importFrom shiny NS tags tagList textOutput tableOutput selectInput uiOutput
#' @importFrom bslib nav_panel layout_sidebar sidebar card card_header card_body
#' @importFrom bsicons bs_icon
#' @export
mod_finance4_ui1 <- function(id) {
  ns <- shiny::NS(id)

  bslib::nav_panel(
    title = "Filtres",
    # Masquer min/max affichés au-dessus des poignées sliderInput
    shiny::tags$style(shiny::HTML(
      ".irs-min, .irs-max { display: none !important; }"
    )),
    icon  = bsicons::bs_icon("sliders"),

    bslib::layout_sidebar(
      fill = TRUE,

      # ── Sidebar Sélection ───────────────────────────────────────────────
      sidebar = bslib::sidebar(
        title = "Sélection",
        width = 230,

        shiny::selectInput(ns("preset"), "Préréglage :",
                           choices  = c("Aucun" = "", names(.presets_defs3)),
                           selected = ""),
        shiny::tags$hr(class = "my-1"),
        shiny::selectInput(ns("secteur_f"), "Secteur :",
                           choices = "Tous", selected = "Tous"),
        shiny::tags$hr(class = "my-1"),
        .build_checkbox_ui2(ns, .filter_defs2)
      ),

      bslib::layout_sidebar(
        fill = TRUE,

        # ── Sidebar Filtres actifs ────────────────────────────────────────
        sidebar = bslib::sidebar(
          title = "Filtres actifs",
          open  = "always",
          width = 245,
          shiny::uiOutput(ns("sliders_dynamiques"))
        ),

        # ── Tableau compagnies ────────────────────────────────────────────
        bslib::card(
          fill = TRUE,
          bslib::card_header(
            class = "d-flex justify-content-between align-items-center",
            shiny::tags$b("Compagnies retenues"),
            shiny::textOutput(ns("n_filtrees4"), inline = TRUE)
          ),
          bslib::card_body(
            style = "overflow-y:auto; padding:0.5rem;",
            shiny::tableOutput(ns("table_filtrees4"))
          )
        )
      )
    )
  )
}

# ── UI 2 — Onglet Détail compagnie ───────────────────────────────────────────

#' Onglet Détail compagnie du module analyse boursière v4
#'
#' @param id Identifiant du module
#' @return `bslib::nav_panel`
#' @importFrom shiny NS tags tagList selectInput textOutput uiOutput plotOutput
#' @importFrom bslib nav_panel layout_columns card card_header card_body
#' @importFrom bsicons bs_icon
#' @export
mod_finance4_ui2 <- function(id) {
  ns <- shiny::NS(id)

  bslib::nav_panel(
    title    = "Détail compagnie",
    fillable = FALSE,
    icon     = bsicons::bs_icon("building"),

    # ── Sélecteur + barre d'info ──────────────────────────────────────────
    shiny::tags$div(
      class = "d-flex align-items-center gap-3 mb-3 flex-wrap",
      shiny::tags$div(style = "min-width:300px; flex:1;",
                      shiny::selectInput(ns("symbol"), NULL,
                                         choices = NULL, width = "100%")),
      shiny::uiOutput(ns("info_bar4"))
    ),

    bslib::layout_columns(
      col_widths = c(3, 6, 3),

      # ── Colonne gauche ──────────────────────────────────────────────────
      shiny::tagList(
        bslib::card(
          bslib::card_header(
            class = "d-flex justify-content-between align-items-center",
            shiny::tags$b("Qualité \u2014 Rentabilit\u00e9 & Marges"),
            shiny::tags$small(class = "text-muted",
                              shiny::textOutput(ns("secteur_detail4"), inline = TRUE))
          ),
          bslib::card_body(style = "padding:0.5rem;",
                           shiny::uiOutput(ns("tableau_rentabilite4")))
        ),
        bslib::card(
          bslib::card_header(shiny::tags$b("Valorisation")),
          bslib::card_body(style = "padding:0.5rem;",
                           shiny::uiOutput(ns("tableau_valorisation4")))
        )
      ),

      # ── Colonne centrale ────────────────────────────────────────────────
      shiny::tagList(
        bslib::card(
          fill = FALSE,
          bslib::card_header(shiny::tags$b("Croissance \u2014 Co. vs Secteur vs Industrie")),
          bslib::card_body(style = "padding:0.5rem; overflow-x:auto; overflow-y:visible;",
                           shiny::uiOutput(ns("tableau_croissance4")))
        ),
        bslib::card(
          fill = FALSE,
          bslib::card_header(
            class = "d-flex justify-content-between align-items-center",
            shiny::tags$b("Bon moment pour acheter ?"),
            shiny::selectInput(ns("duree_graph4"), NULL,
                               choices  = c("1 an" = 1, "3 ans" = 3,
                                            "5 ans" = 5, "10 ans" = 10),
                               selected = 1, width = "120px")
          ),
          bslib::card_body(
            shiny::plotOutput(ns("graph_buy4"), height = "220px"),
            shiny::uiOutput(ns("buy_signal_ui4"))
          )
        )
      ),

      # ── Colonne droite ──────────────────────────────────────────────────
      shiny::tagList(
        bslib::card(
          bslib::card_header(shiny::tags$b("Dividendes")),
          bslib::card_body(style = "padding:0.5rem;",
                           shiny::uiOutput(ns("tableau_dividendes4")))
        ),
        bslib::card(
          bslib::card_header(shiny::tags$b("Structure financi\u00e8re")),
          bslib::card_body(style = "padding:0.5rem;",
                           shiny::uiOutput(ns("tableau_structure4")))
        )
      )
    )
  )
}

# ── UI complète ───────────────────────────────────────────────────────────────

#' UI complète du module analyse boursière v4
#'
#' @param id Identifiant du module
#' @return `bslib::navset_bar`
#' @importFrom bslib navset_bar
#' @export
mod_finance4_ui <- function(id) {
  bslib::navset_bar(
    mod_finance4_ui1(id),
    mod_finance4_ui2(id)
  )
}

# ── Server ────────────────────────────────────────────────────────────────────

#' Serveur du module analyse boursière v4
#'
#' @param id  Identifiant du module
#' @param con Connexion DBI active (PostgreSQL)
#'
#' @importFrom shiny moduleServer reactive req observe observeEvent renderText
#'   renderTable renderUI renderPlot updateSelectInput updateCheckboxGroupInput
#'   updateSliderInput checkboxInput plotOutput
#' @importFrom dplyr tbl collect select filter mutate arrange group_by summarise
#'   across all_of any_of desc slice_tail left_join starts_with transmute if_else
#' @importFrom DBI dbReadTable dbGetQuery
#' @importFrom scales dollar percent
#' @importFrom lubridate years
#' @importFrom ggplot2 ggplot aes geom_ribbon geom_line scale_y_continuous
#'   labs theme_minimal theme element_blank margin
#' @importFrom tidyr drop_na
#'
#' @export
mod_finance4_server <- function(id, con) {
  shiny::moduleServer(id, function(input, output, session) {

    # =========================================================================
    # Chargement depuis les tables pré-calculées
    # =========================================================================

    message("  [1/5] quality_build...")
    quality <- DBI::dbReadTable(con, "quality_build") |>
      dplyr::mutate(
        date_stmts = as.Date(date_stmts),
        filingdate = as.Date(filingdate)
      )

    message("  [2/5] dividendes_build...")
    div_build <- DBI::dbReadTable(con, "dividendes_build") |>
      dplyr::mutate(
        last_div_date       = as.Date(last_div_date),
        last_special_date   = as.Date(last_special_date),
        last_irregular_date = as.Date(last_irregular_date)
      )

    message("  [3/5] cagr_stmts_build + cagr_price_build...")
    cagr_stmts <- DBI::dbReadTable(con, "cagr_stmts_build") |>
      dplyr::select(symbol, dplyr::starts_with("cagr_"))

    cagr_price <- DBI::dbReadTable(con, "cagr_price_build") |>
      dplyr::select(symbol, cagr_1y, cagr_3y, cagr_5y) |>
      dplyr::mutate(cagr_10y = NA_real_)  # placeholder

    message("  [4/5] profils...")
    profile_data <- dplyr::tbl(con, "cies_profile_build") |>
      dplyr::select(symbol, companyname) |>
      dplyr::collect()

    message("  [5/5] Jointure base_data4...")
    base_data4 <- quality |>
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
    cols_med4 <- c("roa", "roe", "m_brut", "m_ebitda", "m_net", "fcf_rev",
                   "ratio_courant", "d_actif", "couv_interet",
                   "p_to_s_calc", "p_to_ebd_calc", "pe_calc", "peg_calc")

    secteur_med4 <- base_data4 |>
      dplyr::group_by(sector) |>
      dplyr::summarise(
        dplyr::across(dplyr::all_of(cols_med4),
                      ~ stats::median(.x, na.rm = TRUE)),
        .groups = "drop"
      )

    cagr_cols_med <- c("cagr_1_is_revenue", "cagr_1_is_ebitda",
                       "cagr_1_is_epsdiluted", "cagr_1_cf_freecashflow")

    secteur_cagr_med4 <- base_data4 |>
      dplyr::group_by(sector) |>
      dplyr::summarise(
        dplyr::across(dplyr::any_of(cagr_cols_med),
                      ~ stats::median(.x, na.rm = TRUE)),
        .groups = "drop"
      )

    industrie_cagr_med4 <- base_data4 |>
      dplyr::group_by(industry) |>
      dplyr::summarise(
        dplyr::across(dplyr::any_of(cagr_cols_med),
                      ~ stats::median(.x, na.rm = TRUE)),
        .groups = "drop"
      )

    # =========================================================================
    # Préréglages
    # =========================================================================

    shiny::observeEvent(input$preset, {
      shiny::req(nchar(input$preset) > 0)
      p    <- .presets_defs3[[input$preset]]
      cats <- unique(sapply(.filter_defs2, `[[`, "cat"))
      for (cat in cats) {
        cat_id   <- paste0("cat_", gsub("[^a-z]", "_", tolower(cat)))
        defs_cat <- Filter(function(d) d$cat == cat, .filter_defs2)
        ids_cat  <- sapply(defs_cat, `[[`, "id")
        shiny::updateCheckboxGroupInput(session, cat_id,
                                        selected = intersect(p$actifs, ids_cat))
      }
      session$onFlushed(once = TRUE, function() {
        for (fid in names(p$valeurs)) {
          shiny::updateSliderInput(session, paste0("f_", fid),
                                   value = p$valeurs[[fid]])
        }
      })
    }, ignoreInit = TRUE)

    # =========================================================================
    # Filtre secteur (timing-safe)
    # =========================================================================

    secteurs <- c("Tous", sort(unique(stats::na.omit(base_data4$sector))))
    shiny::observeEvent(input$secteur_f, {
      shiny::updateSelectInput(session, "secteur_f",
                               choices  = secteurs,
                               selected = "Tous")
    }, once = TRUE, ignoreNULL = TRUE, ignoreInit = FALSE)

    # =========================================================================
    # Filtres actifs
    # =========================================================================

    filtres_actifs4 <- shiny::reactive({
      cats    <- unique(sapply(.filter_defs2, `[[`, "cat"))
      checked <- lapply(cats, function(cat) {
        input[[paste0("cat_", gsub("[^a-z]", "_", tolower(cat)))]]
      })
      unlist(Filter(Negate(is.null), checked))
    })

    # Sliders dynamiques — valeurs courantes conservées lors du re-render
    output$sliders_dynamiques <- shiny::renderUI({
      actifs <- filtres_actifs4()
      # Lire les valeurs actuelles avant que le re-render ne les écrase
      valeurs_courantes <- stats::setNames(
        lapply(.filter_defs2, function(d) input[[paste0("f_", d$id)]]),
        sapply(.filter_defs2, `[[`, "id")
      )
      .build_sliders_actifs2(ns = session$ns, defs = .filter_defs2,
                             actifs = actifs, valeurs_courantes = valeurs_courantes)
    })

    # =========================================================================
    # Filtrage réactif
    # =========================================================================

    df_filtres4 <- shiny::reactive({
      df     <- base_data4
      actifs <- filtres_actifs4()

      if (!is.null(input$secteur_f) && input$secteur_f != "Tous")
        df <- df |> dplyr::filter(sector == input$secteur_f)

      for (d in .filter_defs2) {
        if (!d$id %in% actifs) next

        # ── Filtre binaire (checkbox) ──────────────────────────────────────
        if (isTRUE(d$type == "binary")) {
          if (isTRUE(input[[paste0("f_", d$id)]])) {
            col_vals <- df[[d$col]]
            df <- df[!is.na(col_vals) & col_vals > 0, ]
          }
          next
        }

        # ── Filtre slider ──────────────────────────────────────────────────
        val <- input[[paste0("f_", d$id)]]
        if (is.null(val)) next
        seuil_val <- if (d$fmt == "pct") val / 100 else val
        col_vals  <- df[[d$col]]

        if (d$seuil == "min") {
          df <- df[!is.na(col_vals) & col_vals >= seuil_val, ]
        } else if (isTRUE(d$no_negative)) {
          # Filtre "max" avec exclusion des valeurs négatives (ex: FCF Payout)
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

    output$n_filtrees4 <- shiny::renderText({
      paste0(nrow(df_filtres4()), " compagnies")
    })

    output$table_filtrees4 <- shiny::renderTable({
      df <- df_filtres4() |> dplyr::arrange(ratio_moyen)
      if (nrow(df) == 0)
        return(data.frame(Message = "Aucune compagnie ne correspond aux filtres."))
      df |> dplyr::transmute(
        Ticker    = symbol,
        Compagnie = companyname,
        Secteur   = sector,
        `Mkt Cap` = dplyr::if_else(
          is.na(mktcap_m), "N/D",
          dplyr::case_when(
            mktcap_m >= 200000 ~ paste0(round(mktcap_m / 1000, 1), " T"),
            mktcap_m >=   2000 ~ paste0(round(mktcap_m / 1000, 1), " G"),
            TRUE               ~ paste0(round(mktcap_m), " M")
          )
        ),
        `BR moyen` = dplyr::if_else(
          is.na(ratio_moyen), "N/D",
          scales::percent(ratio_moyen, accuracy = 1)
        )
      )
    }, striped = TRUE, hover = TRUE, bordered = FALSE,
       spacing = "xs", width = "100%")

    # Sync sélecteur symbole
    shiny::observe({
      df <- df_filtres4() |> dplyr::arrange(symbol)
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
    # Données réactives pour le symbole sélectionné
    # =========================================================================

    donnees_symbol4 <- shiny::reactive({
      shiny::req(input$symbol, nchar(input$symbol) > 0)
      base_data4 |> dplyr::filter(symbol == input$symbol)
    })

    # Historique valorisation pour le graphique (chargé à la demande)
    val_hist4 <- shiny::reactive({
      shiny::req(input$symbol, nchar(input$symbol) > 0)
      dplyr::tbl(con, "valuation_build") |>
        dplyr::filter(symbol == !!input$symbol) |>
        dplyr::collect() |>
        dplyr::mutate(date = as.Date(date)) |>
        dplyr::arrange(date)
    })

    val_hist4_filtered <- shiny::reactive({
      n_years <- as.numeric(shiny::req(input$duree_graph4))
      val_hist4() |>
        dplyr::filter(date >= Sys.Date() - lubridate::years(n_years))
    })

    # Dernière ligne valuation (pour les profits estimés)
    val_latest4 <- shiny::reactive({
      df <- val_hist4()
      if (nrow(df) == 0) return(NULL)
      df |> dplyr::arrange(date) |> dplyr::slice_tail(n = 1)
    })

    # =========================================================================
    # Barre d'info compagnie
    # =========================================================================

    output$info_bar4 <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol4()) > 0)
      d       <- donnees_symbol4()
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
    # Tableau Rentabilité & Marges
    # =========================================================================

    output$secteur_detail4 <- shiny::renderText({
      shiny::req(nrow(donnees_symbol4()) > 0)
      sec <- donnees_symbol4()$sector
      if (is.na(sec)) return("")
      paste("vs.", sec)
    })

    output$tableau_rentabilite4 <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol4()) > 0)
      d   <- donnees_symbol4()
      sec <- d$sector
      ref <- secteur_med4 |> dplyr::filter(sector == sec)
      r   <- if (nrow(ref) == 1) ref else
        as.data.frame(as.list(stats::setNames(
          rep(NA_real_, length(cols_med4)), cols_med4)))

      roa5 <- d$roa_moy5
      roe5 <- d$roe_moy5

      shiny::tags$table(
        class = "table table-sm table-hover mb-0",
        shiny::tags$thead(shiny::tags$tr(
          shiny::tags$th("Ratio"),
          shiny::tags$th(class = "text-end", "Cie"),
          shiny::tags$th(class = "text-end text-muted", "Secteur"),
          shiny::tags$th(class = "text-center", "")
        )),
        shiny::tags$tbody(
          .section_qualite("Rentabilit\u00e9"),
          .lq2("ROA",         .fmt_pct2(d$roa),    .fmt_pct2(r$roa),    .sig2(d$roa,    r$roa)),
          .lq2("ROE",         .fmt_pct2(d$roe),    .fmt_pct2(r$roe),    .sig2(d$roe,    r$roe)),
          .lq2("Moy. ROA 5a", .fmt_pct2(roa5),     "\u2014",            .sig2(roa5,     r$roa)),
          .lq2("Moy. ROE 5a", .fmt_pct2(roe5),     "\u2014",            .sig2(roe5,     r$roe)),
          .section_qualite("Marges"),
          .lq2("Marge brute",  .fmt_pct2(d$m_brut),  .fmt_pct2(r$m_brut),  .sig2(d$m_brut,  r$m_brut)),
          .lq2("Marge EBITDA", .fmt_pct2(d$m_ebitda),.fmt_pct2(r$m_ebitda),.sig2(d$m_ebitda,r$m_ebitda)),
          .lq2("Marge nette",  .fmt_pct2(d$m_net),   .fmt_pct2(r$m_net),   .sig2(d$m_net,   r$m_net)),
          .lq2("Marge FCF",    .fmt_pct2(d$fcf_rev), .fmt_pct2(r$fcf_rev), .sig2(d$fcf_rev, r$fcf_rev))
        )
      )
    })

    # =========================================================================
    # Tableau Valorisation
    # =========================================================================

    output$tableau_valorisation4 <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol4()) > 0)
      d   <- donnees_symbol4()
      sec <- d$sector
      ref <- secteur_med4 |> dplyr::filter(sector == sec)
      r   <- if (nrow(ref) == 1) ref else
        as.data.frame(as.list(stats::setNames(
          rep(NA_real_, length(cols_med4)), cols_med4)))

      shiny::tags$table(
        class = "table table-sm table-hover mb-0",
        shiny::tags$thead(shiny::tags$tr(
          shiny::tags$th("Ratio"),
          shiny::tags$th(class = "text-end", "Cie"),
          shiny::tags$th(class = "text-end text-muted", "Secteur"),
          shiny::tags$th(class = "text-center", "")
        )),
        shiny::tags$tbody(
          .lq2("P/S",      .fmt_x2(d$p_to_s_calc),
               .fmt_x2(r$p_to_s_calc),
               .sig2(d$p_to_s_calc,   r$p_to_s_calc,   inverse = TRUE)),
          .lq2("P/EBITDA", .fmt_x2(d$p_to_ebd_calc),
               .fmt_x2(r$p_to_ebd_calc),
               .sig2(d$p_to_ebd_calc, r$p_to_ebd_calc, inverse = TRUE)),
          .lq2("P/E",      .fmt_x2(d$pe_calc),
               .fmt_x2(r$pe_calc),
               .sig2(d$pe_calc,       r$pe_calc,        inverse = TRUE)),
          .lq2("PEG",      .fmt_num2(d$peg_calc),
               .fmt_num2(r$peg_calc),
               .sig2(d$peg_calc,      r$peg_calc,       inverse = TRUE))
        )
      )
    })

    # =========================================================================
    # Tableau Croissance — Co. 1a / Sect. / Ind. / CAGR 3a / 5a / 10a
    # =========================================================================

    output$tableau_croissance4 <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol4()) > 0)
      d   <- donnees_symbol4()
      sec <- d$sector
      ind <- d$industry

      s_med <- secteur_cagr_med4   |> dplyr::filter(sector   == sec)
      i_med <- industrie_cagr_med4 |> dplyr::filter(industry == ind)

      get_med <- function(df, col)
        if (nrow(df) == 1 && col %in% names(df)) df[[col]] else NA_real_

      px1 <- d$cagr_1y; px3 <- d$cagr_3y; px5 <- d$cagr_5y; px10 <- NA_real_

      ligne_cagr <- function(label, c1, s1, i1, c3, c5, c10) {
        shiny::tags$tr(
          shiny::tags$td(class = "small", label),
          .td_cagr3(c1,  px1),
          .td_ref3(s1),
          .td_ref3(i1),
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
            d$cagr_3_cf_freecashflow, d$cagr_5_cf_freecashflow, d$cagr_10_cf_freecashflow)
        )
      )
    })

    # =========================================================================
    # Graphique bandes buy/sell
    # =========================================================================

    output$graph_buy4 <- shiny::renderPlot({
      df  <- val_hist4_filtered()
      met <- if (is.null(input$metrique_graph4) ||
                 !input$metrique_graph4 %in% names(.metric_val_cols3))
               "P/S" else input$metrique_graph4
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
    # Indicateurs buy signal — 4 boîtes cliquables + Gordon
    # =========================================================================

    output$buy_signal_ui4 <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol4()) > 0)
      d  <- donnees_symbol4()
      vl <- val_latest4()

      met_actif <- if (is.null(input$metrique_graph4) ||
                       !input$metrique_graph4 %in% names(.metric_val_cols3))
                     "P/S" else input$metrique_graph4

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
        list(label = "Profit P/E dil.", met = "P/E dil.", profit = calc_profit("caution_pe_dil"))
      )

      boite_profit <- function(b) {
        val    <- b$profit
        actif  <- isTRUE(b$met == met_actif)
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
          session$ns("metrique_graph4"), b$met
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
        class = "d-flex gap-1 mt-2 flex-wrap",
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
    # Tableau Dividendes (depuis dividendes_build)
    # =========================================================================

    output$tableau_dividendes4 <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol4()) > 0)
      d <- donnees_symbol4()

      flag_special   <- if (isTRUE(d$has_special))
        paste0("Oui (", format(d$last_special_date, "%Y-%m-%d"), ")") else "Non"
      flag_irregular <- if (isTRUE(d$has_irregular))
        paste0("Oui (", format(d$last_irregular_date, "%Y-%m-%d"), ")") else "Non"

      # FCF Payout : afficher valeur réelle même si négative (signal important)
      txt_fcf_pay <- if (is.na(d$fcf_payout)) "N/D"
                     else scales::percent(d$fcf_payout, accuracy = 0.1)
      txt_fcf_cov <- .fmt_x2(d$fcf_coverage)

      lignes <- list(
        list("Yield estim\u00e9",        .fmt_pct2(d$yield, 0.1)),
        list("Croissance r\u00e9guli\u00e8re", if (isTRUE(d$croissance_reguliere)) "Oui" else "Non"),
        list("CAGR div. 1a",         .fmt_pct2(d$cagr_div_1a, 1)),
        list("CAGR div. 3a",         .fmt_pct2(d$cagr_div_3a, 1)),
        list("CAGR div. 5a",         .fmt_pct2(d$cagr_div_5a, 1)),
        list("CAGR div. 10a",        .fmt_pct2(d$cagr_div_10a, 1)),
        list("FCF Payout",           txt_fcf_pay),
        list("FCF Coverage",         txt_fcf_cov),
        list("Dividende sp\u00e9cial",   flag_special),
        list("Div. irr\u00e9gulier",     flag_irregular)
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

    # =========================================================================
    # Tableau Structure financière
    # =========================================================================

    output$tableau_structure4 <- shiny::renderUI({
      shiny::req(nrow(donnees_symbol4()) > 0)
      d <- donnees_symbol4()

      mktcap_cat <- if (is.na(d$mktcap_m)) "N/D"
                    else if (d$mktcap_m >= 200000) "Mega Cap"
                    else if (d$mktcap_m >=  10000) "Large Cap"
                    else if (d$mktcap_m >=   2000) "Mid Cap"
                    else "Small Cap"

      lignes <- list(
        list("Dette / Actif",       .fmt_pct2(d$d_actif)),
        list("Couverture int\u00e9r\u00eats", .fmt_x2(d$couv_interet)),
        list("Ratio liquidit\u00e9",     .fmt_x2(d$ratio_courant)),
        list("Market Cap",          mktcap_cat)
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
