# helpers_finance.R â€” Helpers partagÃ©s des modules d'analyse boursiÃ¨re
#
# Extrait de mod_finance4.R (qui a Ã©tÃ© supprimÃ©). Ces helpers sont rÃ©utilisÃ©s
# par mod_finance6.R (mÃªme namespace package) : tableaux qualitÃ©, filtres,
# prÃ©rÃ©glages, formatage et signal de croissance.
#
# Sources de donnÃ©es : quality_build, dividendes_build,
#   cagr_stmts_build, cagr_price_build, valuation_build (graphique)

# â”€â”€ Helpers â€” tableaux qualitÃ© â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

# â”€â”€ Helpers â€” filtres â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

# DÃ©finitions des filtres
# fmt         : "pct" â†’ slider 0-N, filtre /100 | "dec" â†’ dÃ©cimal | "num" â†’ brut
# seuil       : "min" â†’ cie >= valeur | "max" â†’ cie <= valeur
# type        : absent = slider | "binary" = checkbox (pas de slider)
# no_negative : TRUE â†’ exclut aussi les valeurs nÃ©gatives (filtre "max" uniquement)
# div_sub     : TRUE â†’ filtre dividende conditionnel (masquÃ© si "avec_div" non cochÃ©)
# default     : TRUE = cochÃ© au dÃ©marrage
.filter_defs2 <- list(
  list(id="roa",      label="ROA",              cat="RentabilitÃ©", col="roa",                  min=0, max=60,   step=1,    fmt="pct", seuil="min", default=TRUE),
  list(id="roe",      label="ROE",              cat="RentabilitÃ©", col="roe",                  min=0, max=60,   step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="roa_moy5", label="ROA moy. 5a",      cat="RentabilitÃ©", col="roa_moy5",             min=0, max=30,   step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="roe_moy5", label="ROE moy. 5a",      cat="RentabilitÃ©", col="roe_moy5",             min=0, max=60,   step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="m_brut",   label="Marge brute",      cat="RentabilitÃ©", col="m_brut",               min=0, max=100,  step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="m_ebitda", label="Marge EBITDA",     cat="RentabilitÃ©", col="m_ebitda",             min=0, max=60,   step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="m_net",    label="Marge nette",      cat="RentabilitÃ©", col="m_net",                min=0, max=50,   step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="cagr_rev", label="Sales Growth 3a",  cat="Croissance",  col="cagr_3_is_revenue",    min=0, max=50,   step=1,    fmt="pct", seuil="min", default=TRUE),
  list(id="cagr_ebd", label="EBITDA Growth 3a", cat="Croissance",  col="cagr_3_is_ebitda",     min=0, max=50,   step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="cagr_eps", label="EPS Growth 3a",    cat="Croissance",  col="cagr_3_is_epsdiluted", min=0, max=50,   step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="br_pts",   label="BR Sales",         cat="Buy Ratio",   col="r_pts",  min=0, max=1, step=0.05, fmt="dec", seuil="max", default=TRUE,  val=0.1),
  list(id="br_ebd",   label="BR EBITDA",        cat="Buy Ratio",   col="r_ebd",  min=0, max=1, step=0.05, fmt="dec", seuil="max", default=FALSE, val=0.1),
  list(id="br_pe",    label="BR EPS",           cat="Buy Ratio",   col="r_pe",   min=0, max=1, step=0.05, fmt="dec", seuil="max", default=FALSE, val=0.1),
  list(id="br_ped",   label="BR EPS dil.",      cat="Buy Ratio",   col="r_ped",  min=0, max=1, step=0.05, fmt="dec", seuil="max", default=FALSE, val=0.1),
  list(id="r_courant",label="Ratio courant",    cat="SoliditÃ©",    col="ratio_courant",        min=0, max=5,    step=0.1,  fmt="dec", seuil="min", default=FALSE),
  list(id="fcf_rev",  label="FCF / Revenus",    cat="SoliditÃ©",    col="fcf_rev",              min=0, max=50,   step=1,    fmt="pct", seuil="min", default=FALSE),
  list(id="pppi",     label="PPPI max.",         cat="SoliditÃ©",    col="pppi",                 min=0, max=100,  step=5,    fmt="pct", seuil="max", default=FALSE, val=50),
  list(id="mktcap",   label="Mkt Cap ($M)",     cat="MarchÃ©",      col="mktcap_m",             min=0, max=3000, step=50,   fmt="num", seuil="min", default=FALSE),
  # Filtres dividendes conditionnels (div_sub=TRUE) â€” visibles uniquement si "avec_div" cochÃ©
  list(id="yield",    label="Yield min.",       cat="Dividendes",  col="yield",      min=0, max=10,  step=0.5, fmt="pct", seuil="min", default=FALSE, val=2,  div_sub=TRUE),
  list(id="cagr_div5",label="CAGR Div. 5a",    cat="Dividendes",  col="cagr_div_5a",min=0, max=20,  step=1,   fmt="pct", seuil="min", default=FALSE, val=3,  div_sub=TRUE),
  list(id="fcf_pay",  label="FCF Payout max.", cat="Dividendes",   col="fcf_payout", min=0, max=100, step=5,   fmt="pct", seuil="max", default=FALSE, val=80, div_sub=TRUE, no_negative=TRUE)
)

# PrÃ©rÃ©glages de filtres
.presets_defs3 <- list(
  "Croissance qualitÃ©" = list(
    actifs  = c("roa", "m_ebitda", "cagr_rev", "cagr_eps", "br_pts"),
    valeurs = list(roa = 10, m_ebitda = 15, cagr_rev = 8, cagr_eps = 8, br_pts = 0.5)
  ),
  "Dividendes stables" = list(
    actifs  = c("roa", "fcf_rev", "r_courant", "br_pts", "avec_div", "yield"),
    valeurs = list(roa = 5, fcf_rev = 8, r_courant = 1.2, br_pts = 0.7, yield = 2)
  ),
  "Valeur dÃ©fensive" = list(
    actifs  = c("m_brut", "m_net", "r_courant", "br_pts", "br_ebd"),
    valeurs = list(m_brut = 30, m_net = 8, r_courant = 1.5, br_pts = 0.5, br_ebd = 0.5)
  )
)

# Checkboxes groupÃ©es par catÃ©gorie (sidebar SÃ©lection) â€” exclut les div_sub
.build_checkbox_ui2 <- function(ns, defs) {
  defs_static <- Filter(function(d) !isTRUE(d$div_sub), defs)
  cats <- unique(sapply(defs_static, `[[`, "cat"))
  shiny::tagList(lapply(cats, function(cat) {
    defs_cat <- Filter(function(d) d$cat == cat, defs_static)
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
# valeurs_courantes : liste nommÃ©e par id â†’ valeur actuelle de l'input
#   â†’ permet de conserver la valeur quand on ajoute/retire un filtre
.build_sliders_actifs2 <- function(ns, defs, actifs, valeurs_courantes = list()) {
  if (length(actifs) == 0) {
    return(shiny::tags$p(
      class = "text-muted small fst-italic",
      "Cochez des filtres dans la sÃ©lection."
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

        # â”€â”€ Filtre slider â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        # PrioritÃ© : valeur courante > val dÃ©finie > min/max selon seuil
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

# Mapping mÃ©trique â†’ colonnes valuation_build
.metric_val_cols3 <- list(
  "P/S"      = list(buy = "buy_p_to_s",      sell = "sell_p_to_s",      caution = "caution_p_to_s"),
  "P/EBITDA" = list(buy = "buy_p_to_ebitda", sell = "sell_p_to_ebitda", caution = "caution_p_to_ebitda"),
  "P/E"      = list(buy = "buy_pe",           sell = "sell_pe",          caution = "caution_pe"),
  "P/E dil." = list(buy = "buy_pe_dil",       sell = "sell_pe_dil",      caution = "caution_pe_dil")
)
