library(data.table)
library(magrittr)
library(ggplot2)
library(cowplot)

grid <- fread("cache/bias-shape=5-scale=0.10_gain-shape=100-scale=0.10_grid.csv")

sigmoid <- function(n, b, g) {
  1/(1 + exp(-g * (n-b)))
}

# plot samples of joint space
gridDexes <- 1:nrow(grid)
dexSamples <- sample(gridDexes, 1000, prob = grid$jointP, replace = TRUE)
gridSamples <- grid[dexSamples]
gridSamples[, N := .N, by = c("bias", "gain")]
gridSamplesP <- ggplot(data = gridSamples) + geom_contour_filled(aes(x = bias, y = gain, z = N))

# plot marginal of samples
sampleMarginalB <- gridSamples[, .(margN = sum(N)), by=bias]
sampleMarginalG <- gridSamples[, .(margN = sum(N)), by=gain]
ggplot() + geom_col(aes(x = sampleMarginalB$bias, y = sampleMarginalB$margN))
ggplot() + geom_col(aes(x = sampleMarginalG$gain, y = sampleMarginalG$margN))

# sigmoid function over 0-3 blickets
ns <- 0:3
getActivationDT <- function(dt) {
  stopifnot(nrow(dt) == 1)
  ys = sapply(ns, function(x) sigmoid(x, dt$bias, dt$gain))
  data.table(ns, ys)
}
 

gammaPdf <- function(x, shape, scale) {
  dgamma(x, shape, scale = scale)
}

allLines <- gridSamples[, getActivationDT(.SD), by=rownames(gridSamples)]
allLinesP <- ggplot(allLines, aes(x = ns, y = ys, group = rownames)) +
  geom_line(alpha = 0.1)

# then combine with the top row for final plot
finalPlot <- plot_grid(gridSamplesP, allLinesP, ncol = 2, labels = "AUTO")
finalPlot

save_plot(filename = "cache/gamma_sigmoid_sim.pdf", plot = finalPlot, base_height = 3, base_width = 6)