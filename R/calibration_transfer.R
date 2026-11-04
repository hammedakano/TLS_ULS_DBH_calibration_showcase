# Calibration transfer of a drone (ULS) DBH model to a new plot with a few TLS trees
#
# Showcase component of the TLS to ULS DBH transfer analysis by Hammed Akano.
# This script reproduces the plot by plot comparison of modelled and field measured
# stand mean DBH (layout after Finn et al. 2026, Remote Sensing 18, 2644).
#
# Design
#   Inputs   drone (ULS leaf-on) tree metrics: height, crown projection area, crown base height, position
#   Label    TLS DBH
#   Truth    tape DBH (used only to score the result)
#   Test     leave one plot out. Each tape plot is predicted by a model trained on the other plots,
#            then calibrated with that plot's own TLS trees.
#
# Methods compared
#   pooled          log-log allometry trained on the other plots, no local trees
#   size_dependent  the same allometry in a mixed model with a random intercept and a random slope on
#                   log height per plot. The target plot's TLS trees estimate its own stand effect.
#   additive_tls    additive TLS distribution: the plot's TLS DBH distribution assigned to the drone trees by rank
#
# Run from the repository folder:  Rscript R/calibration_transfer.R
# Requires R (>= 4.1) and lme4.

suppressPackageStartupMessages(library(lme4))
dir.create("results", showWarnings = FALSE)

# ---- 1  Drone tree metrics and neighbourhood (competition) variables ----
d <- read.csv("data/trees_uls_tls_tape.csv", stringsAsFactors = FALSE)
d$h   <- d$uls_on_h
d$cpa <- d$uls_on_cpa
d$cl  <- pmax(d$h - pmax(ifelse(is.na(d$uls_on_cbh), 0.1, d$uls_on_cbh), 0.1), 0.5)   # crown length (m)
d$nn <- NA; d$hegyi <- NA
for (p in unique(d$plot)) {
  i <- which(d$plot == p)
  D <- as.matrix(dist(d[i, c("x", "y")])); diag(D) <- Inf
  d$nn[i] <- pmin(apply(D, 1, min), 15)                                    # nearest neighbour distance (m)
  d$hegyi[i] <- sapply(seq_along(i), function(k) {                         # Hegyi competition index, 8 m radius
    j <- D[k, ] < 8; sum((d$cpa[i][j] / d$cpa[i][k]) / D[k, j]) })
}

# log(DBH) = b0 + b1 log h + b2 log CPA + b3 log crown length + b4 log nn + b5 log(1 + Hegyi)
X <- function(z) data.frame(lh = log(z$h), lc = log(z$cpa), ll = log(z$cl),
                            lnn = log(z$nn), lheg = log1p(z$hegyi), plot = z$plot)
f_fixed <- ly ~ lh + lc + ll + lnn + lheg
tls <- d[!is.na(d$tls_dbh) & d$tls_dbh > 5, ]                              # trees with a TLS label

# ---- 2  Predict one unseen plot ----
predict_plot <- function(p) {
  train <- tls[tls$plot != p, ]                                            # TLS trees of the other plots
  local <- tls[tls$plot == p, ]                                            # the target plot's own TLS trees
  test  <- d[d$plot == p & !is.na(d$fi_dbh) & d$fi_dbh > 5 & !(d$id %in% local$id), ]   # tape trees, not used for calibration
  Xt <- cbind(X(train), ly = log(train$tls_dbh))
  Xl <- cbind(X(local), ly = log(local$tls_dbh))
  Xn <- X(test)

  # pooled model, no local trees (with the log bias correction sigma^2 / 2)
  m0 <- lm(f_fixed, Xt)
  pooled <- exp(predict(m0, Xn) + summary(m0)$sigma^2 / 2)

  # size-dependent stand effect: random intercept and slope on log height per plot.
  # The target plot enters the fit only through its TLS trees, so its effect is shrunk towards
  # zero when it has few or noisy TLS trees.
  mc <- suppressWarnings(lmer(update(f_fixed, . ~ . + (1 + lh | plot)), rbind(Xt, Xl)))
  re <- ranef(mc)$plot[p, ]
  size_dependent <- exp(predict(mc, Xn, re.form = NA) + re[[1]] + re[[2]] * Xn$lh + sigma(mc)^2 / 2)

  # additive TLS distribution: TLS DBH quantiles assigned by rank of the pooled prediction
  additive_tls <- as.numeric(quantile(local$tls_dbh, rank(pooled) / (nrow(test) + 1)))

  list(field = test$fi_dbh, tls = local$tls_dbh, pooled = pooled,
       size_dependent = size_dependent, additive_tls = additive_tls)
}

# ---- 3  Score each tape plot against the field mean ----
plots <- c("BR01", "BR03", "BR05", "KA09", "KA10", "KA11")
rows <- list()
for (p in plots) {
  M <- predict_plot(p); o <- M$field
  for (m in names(M)) {
    v <- M[[m]]
    rows[[length(rows) + 1]] <- data.frame(
      plot = p, method = m, n = length(v), mean_cm = mean(v), sd_cm = sd(v),
      dev_cm = mean(v) - mean(o), dev_pct = 100 * (mean(v) - mean(o)) / mean(o),
      tree_rmse_pct = if (m %in% c("field", "tls")) NA else 100 * sqrt(mean((v - o)^2)) / mean(o))
  }
}
T <- do.call(rbind, rows)
write.csv(T, "results/plot_table.csv", row.names = FALSE)

# Mean absolute deviation over the five plots with enough tape trees (KA10 has 3)
S <- aggregate(cbind(abs_dev_cm = abs(dev_cm), abs_dev_pct = abs(dev_pct), tree_rmse_pct) ~ method,
               T[T$plot != "KA10" & !(T$method %in% c("field", "tls")), ], mean)
write.csv(S, "results/summary_5_plots.csv", row.names = FALSE)
print(S, digits = 3, row.names = FALSE)
