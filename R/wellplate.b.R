
# This file is part of the jwellplate jamovi module.
#
# wellplateClass draws a plate map (6/12/24/96/384/1536 wells) for
# plate-based experimental data, mirroring the logic of the Python
# `well_plate` package -- https://github.com/zindy/well_plate:
# either a single well-ID column ("A1", "A01") or # separate
# Row/Column columns can be supplied, and the Value column can
# be numeric (continuous colour scale + colourbar) or categorical
# (discrete legend).

#' @importFrom R6 R6Class
#' @export

wellPlateClass <- if (requireNamespace('jmvcore', quietly = TRUE)) R6::R6Class(
    'wellPlateClass',
    inherit = wellPlateBase,
    private = list(

        # ---- plate geometry -------------------------------------------

        .plateSpecs = function() {
            list(
                `6`    = list(rows = 2,  cols = 3),
                `12`   = list(rows = 3,  cols = 4),
                `24`   = list(rows = 4,  cols = 6),
                `96`   = list(rows = 8,  cols = 12),
                `384`  = list(rows = 16, cols = 24),
                `1536` = list(rows = 32, cols = 48)
            )
        },

        # row labels A, B, ..., Z, AA, AB, ... (mirrors the Python module)
        .rowLabels = function(n) {
            labels <- character(n)
            for (i in seq_len(n)) {
                idx <- i - 1
                if (idx < 26) {
                    labels[i] <- LETTERS[idx + 1]
                } else {
                    first  <- LETTERS[(idx %/% 26)]
                    second <- LETTERS[(idx %% 26) + 1]
                    labels[i] <- paste0(first, second)
                }
            }
            labels
        },

        # convert a 1-based linear well number to a "A1"-style key,
        # row-major from the top-left well (1 -> A1, 2 -> A2, ...,
        # nCols -> A<nCols>, nCols+1 -> B1, ...). Returns NA if out of range.
        .indexToWellKey = function(idxStr, nRows, nCols, rowLabels) {
            idx <- suppressWarnings(as.integer(idxStr))
            if (is.na(idx) || idx < 1 || idx > nRows * nCols)
                return(NA_character_)
            rowIdx <- ((idx - 1) %/% nCols) + 1
            colIdx <- ((idx - 1) %% nCols) + 1
            paste0(rowLabels[rowIdx], colIdx)
        },

        # parse a single well identifier -> "A1"-style key, or NA if
        # invalid/missing. Accepts "A1"/"A01"-style strings, or a plain
        # integer treated as a 1-based linear well number (see
        # .indexToWellKey above).
        .parseWellID = function(id, nRows, nCols, rowLabels) {
            if (is.na(id))
                return(NA_character_)
            id <- trimws(as.character(id))
            if (id == '')
                return(NA_character_)
            if (grepl('^[0-9]+$', id))
                return(private$.indexToWellKey(id, nRows, nCols, rowLabels))
            m <- regmatches(id, regexec('^([A-Za-z]+)0*([0-9]+)$', id))[[1]]
            if (length(m) != 3)
                return(NA_character_)
            paste0(toupper(m[2]), as.integer(m[3]))
        },

        # ---- build the full-plate data frame ---------------------------

        .buildData = function() {

            options <- self$options
            data <- self$data

            specs <- private$.plateSpecs()
            spec  <- specs[[options$plateSize]]
            nRows <- spec$rows
            nCols <- spec$cols
            rowLabels <- private$.rowLabels(nRows)

            grid <- expand.grid(rowIdx = seq_len(nRows), colIdx = seq_len(nCols))
            grid$rowLabel <- rowLabels[grid$rowIdx]
            grid$wellKey  <- paste0(grid$rowLabel, grid$colIdx)

            valueVar   <- options$value
            rawValues  <- data[[valueVar]]

            # `value` permits both factor and numeric variables, so jmvcore
            # hands the column back in its raw "dual nature" form -- this is
            # very often a factor (with the real numbers stashed as a hidden
            # attribute), even for variables the user intends as continuous
            # (e.g. whole-number columns jamovi auto-classified as Nominal).
            # is.numeric() on that raw column is therefore unreliable. We
            # instead try to extract real numbers with jmvcore::toNumeric()
            # and only treat the column as categorical if that genuinely
            # fails (i.e. it contains non-numeric text labels).
            origMissing   <- is.na(rawValues)
            numValues     <- suppressWarnings(jmvcore::toNumeric(rawValues))
            isCategorical <- any(is.na(numValues) & !origMissing)

            if (!isCategorical)
                rawValues <- numValues

            if (!is.null(options$wellID) && nzchar(options$wellID)) {

                idVar <- data[[options$wellID]]
                wellKeys <- vapply(
                    idVar, private$.parseWellID, character(1),
                    nRows = nRows, nCols = nCols, rowLabels = rowLabels
                )

            } else if (!is.null(options$rowVar) && !is.null(options$colVar)) {

                rowRaw <- toupper(trimws(as.character(data[[options$rowVar]])))
                colRaw <- suppressWarnings(as.integer(as.character(data[[options$colVar]])))
                ok <- !is.na(rowRaw) & rowRaw != '' & !is.na(colRaw)
                wellKeys <- rep(NA_character_, length(rowRaw))
                wellKeys[ok] <- paste0(rowRaw[ok], colRaw[ok])

            } else {
                return(NULL)
            }

            valuesDF <- data.frame(wellKey = wellKeys, val = rawValues, stringsAsFactors = FALSE)
            valuesDF <- valuesDF[!is.na(valuesDF$wellKey), , drop = FALSE]
            # if a well appears more than once, keep its last non-missing entry
            valuesDF <- valuesDF[!duplicated(valuesDF$wellKey, fromLast = TRUE), , drop = FALSE]

            if (nrow(valuesDF) == 0)
                jmvcore::reject(
                    paste0(
                        'No wells could be recognised from the supplied Well ID ',
                        '/ Row+Column data. Expected values like "A1", "A01", or ',
                        'a plain 1-based well number (e.g. 1-', nRows * nCols,
                        ' for a ', nRows * nCols, '-well plate).'
                    ),
                    code = ''
                )

            merged <- merge(grid, valuesDF, by = 'wellKey', all.x = TRUE, sort = FALSE)
            merged$x <- merged$colIdx
            merged$y <- nRows - merged$rowIdx + 1

            list(
                data          = merged,
                nRows         = nRows,
                nCols         = nCols,
                rowLabels     = rowLabels,
                isCategorical = !is.numeric(rawValues)
            )
        },

        # ---- validation --------------------------------------------------

        .run = function() {

            if (is.null(self$options$value))
                return()

            haveWellID  <- !is.null(self$options$wellID)
            haveRowCol  <- !is.null(self$options$rowVar) && !is.null(self$options$colVar)

            if (!haveWellID && !haveRowCol)
                jmvcore::reject(
                    'Please assign either a Well ID variable, or both a Row and a Column variable.',
                    code = ''
                )

            if (haveWellID && haveRowCol)
                jmvcore::reject(
                    'Please assign a Well ID variable, OR a Row + Column pair, not both.',
                    code = ''
                )
        },

        # ---- plotting ------------------------------------------------------

        # wrap a legend/axis title onto multiple lines so a long variable
        # name (e.g. "log2_fold_change") doesn't claim extra legend width
        # and shrink the plate -- coord_fixed() gives the panel whatever
        # width is left after the legend, so an unbounded single-line
        # title changes the plate's rendered size plot-to-plot.
        # strwrap() alone won't do this: R/statistics variable names are
        # snake_case with no spaces for it to break on, so it wraps
        # nothing. Break at underscores instead, falling back to a hard
        # character break if there's no underscore near the width limit.
        .wrapTitle = function(title, width = 14) {
            title <- as.character(title)
            if (is.na(title) || nchar(title) <= width)
                return(title)

            lines <- character(0)
            remaining <- title
            while (nchar(remaining) > width) {
                chunk   <- substr(remaining, 1, width)
                breakAt <- max(unlist(gregexpr('_', chunk)))
                if (breakAt > width * 0.4) {
                    lines     <- c(lines, substr(remaining, 1, breakAt))
                    remaining <- substr(remaining, breakAt + 1, nchar(remaining))
                } else {
                    lines     <- c(lines, chunk)
                    remaining <- substr(remaining, width + 1, nchar(remaining))
                }
            }
            paste(c(lines, remaining), collapse = '\n')
        },

        .plot = function(image, ggtheme, theme, ...) {

            if (is.null(self$options$value))
                return(FALSE)

            built <- private$.buildData()
            if (is.null(built))
                return(FALSE)

            df        <- built$data
            nRows     <- built$nRows
            nCols     <- built$nCols
            rowLabels <- built$rowLabels
            isCategorical <- built$isCategorical

            options    <- self$options
            wellSize   <- options$wellSize
            shape      <- options$shape
            valueTitle <- options$value

            # ggtheme carries jamovi's default plot styling, which includes
            # a default *discrete* fill palette. If it's added after our own
            # fill scale, it silently overrides it (last scale for a given
            # aesthetic wins in ggplot2) -- so it must go on first, and our
            # explicit scale_fill_* call below must come after it.
            p <- ggplot2::ggplot(df, ggplot2::aes(x = x, y = y)) + ggtheme

            if (shape == 'circle') {
                p <- p + ggforce::geom_circle(
                    data = df,
                    mapping = ggplot2::aes(x0 = x, y0 = y, r = wellSize / 2, fill = val),
                    colour = 'black', linewidth = 0.6, inherit.aes = FALSE
                )
            } else {
                p <- p + ggplot2::geom_tile(
                    ggplot2::aes(fill = val),
                    width = wellSize, height = wellSize,
                    colour = 'black', linewidth = 0.6
                )
            }

            if (isCategorical) {
                cats <- sort(unique(stats::na.omit(as.character(df$val))))
                pal  <- scales::hue_pal()(max(length(cats), 1))
                names(pal) <- cats
                p <- p + ggplot2::scale_fill_manual(
                    values = pal, na.value = 'white',
                    name = private$.wrapTitle(valueTitle), na.translate = FALSE
                )
            } else {
                cmapName <- options$colourScheme
                if (cmapName %in% c('viridis', 'magma', 'plasma', 'cividis')) {
                    p <- p + ggplot2::scale_fill_viridis_c(
                        option = cmapName, na.value = 'white',
                        name = private$.wrapTitle(valueTitle)
                    )
                } else {
                    brewerPalette <- if (cmapName == 'reds') 'Reds' else 'Blues'
                    p <- p + ggplot2::scale_fill_distiller(
                        palette = brewerPalette, direction = 1, na.value = 'white',
                        name = private$.wrapTitle(valueTitle)
                    )
                }
            }

            if (isTRUE(options$crossMissing)) {
                missingWells <- df[is.na(df$val), , drop = FALSE]
                if (nrow(missingWells) > 0) {
                    cs <- wellSize / 2 * 0.7
                    p <- p +
                        ggplot2::geom_segment(
                            data = missingWells,
                            mapping = ggplot2::aes(x = x - cs, xend = x + cs, y = y - cs, yend = y + cs),
                            colour = 'red', linewidth = 0.6, inherit.aes = FALSE
                        ) +
                        ggplot2::geom_segment(
                            data = missingWells,
                            mapping = ggplot2::aes(x = x - cs, xend = x + cs, y = y + cs, yend = y - cs),
                            colour = 'red', linewidth = 0.6, inherit.aes = FALSE
                        )
                }
            }

            if (isTRUE(options$showBorder)) {
                p <- p + ggplot2::annotate(
                    'rect',
                    xmin = 0.5, xmax = nCols + 0.5, ymin = 0.5, ymax = nRows + 0.5,
                    fill = NA, colour = 'black', linewidth = 0.8
                )
            }

            p <- p +
                ggplot2::scale_x_continuous(
                    breaks = 1:nCols, labels = 1:nCols,
                    expand = ggplot2::expansion(add = 0.6)
                ) +
                ggplot2::scale_y_continuous(
                    breaks = 1:nRows, labels = rev(rowLabels),
                    expand = ggplot2::expansion(add = 0.6)
                ) +
                ggplot2::coord_fixed(ratio = 1) +
                ggplot2::theme(
                    panel.grid        = ggplot2::element_blank(),
                    panel.border      = ggplot2::element_blank(),
                    axis.line         = ggplot2::element_blank(),
                    axis.line.x       = ggplot2::element_blank(),
                    axis.line.y       = ggplot2::element_blank(),
                    axis.ticks        = ggplot2::element_blank(),
                    axis.ticks.length = ggplot2::unit(0, 'pt'),
                    axis.title        = ggplot2::element_blank(),
                    axis.title.x      = ggplot2::element_blank(),
                    axis.title.y      = ggplot2::element_blank(),
                    axis.text.x       = ggplot2::element_text(margin = ggplot2::margin(t = 2)),
                    axis.text.y       = ggplot2::element_text(margin = ggplot2::margin(r = 2)),
                    legend.title      = ggplot2::element_text(size = 10, lineheight = 0.9),
                    legend.text       = ggplot2::element_text(size = 9),
                    legend.key.size   = ggplot2::unit(14, 'pt')
                )

            if (!isTRUE(options$showLegend))
                p <- p + ggplot2::theme(legend.position = 'none')

            print(p)
            TRUE
        }
    )
)
