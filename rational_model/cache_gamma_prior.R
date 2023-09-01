library(data.table)
library(magrittr)
library(optparse)
source("helperfuns.R")

parser <- OptionParser()
parser <- add_option(parser, "--bias_shape", type="double", default=NA)
parser <- add_option(parser, "--bias_scale", type="double", default=NA)
parser <- add_option(parser, "--gain_shape", type="double", default=NA)
parser <- add_option(parser, "--gain_scale", type="double", default=NA)

args <- parse_args(parser)

# SET THESE VARS -----
# args <- parse_args(parser, args = c("--bias_shape", 4, "--bias_scale", 0.25, "--gain_shape", 21.00, "--gain_scale", 1.00))

saveGrid <- FALSE
saveDir <- "cache/gamma_priors"
createDirs(saveDir)

# OBS: don't exceed 2 d.p. for param values for the sake of the save file's %.2f formatting

biasStep <- 0.15
gainStep <- 2
biasVals <- seq(0, 3, biasStep)
gainVals <- seq(0, 40, gainStep)

# gamma puts mode at (shape-1)*scale for shape >= 1 and mean at shape*scale

biasShape <- args$bias_shape
biasScale <- args$bias_scale
# dgamma(biasVals, biasShape, scale=biasScale) %>% plot(x = biasVals)

gainShape <- args$gain_shape
gainScale <- args$gain_scale
# dgamma(gainVals, gainShape, scale=gainScale) %>% plot(x = gainVals)

gridWidth <- biasStep*gainStep  # "width" (area) of each grid point, to be used for histogram approximation
savePath <- file.path(saveDir, sprintf("bias-shape=%.2f-scale=%.2f_gain-shape=%.2f-scale=%.2f_width=%.2f_grid.csv", biasShape, biasScale, gainShape, gainScale, gridWidth))

# RUN -----

grid <- expand.grid(biasVals, gainVals) %>% as.data.table()
setnames(grid, colnames(grid), c("bias", "gain"))

gammaCdf <- function(x, shape, scale) {
  pgamma(x, shape, scale = scale)
}

# use the cdf to calculate the probability for each bin (represented by the leftmost value, e.g. 0 represents the 0-1 bin for gain)
biasDT <- data.table(val = biasVals)
biasDT[, cumulative_p := gammaCdf(val, biasShape, biasScale)]
biasDT[, p := shift(cumulative_p, type = "lead") - cumulative_p]
stopifnot(round(sum(biasDT$p, na.rm = TRUE), 2) == 1)

gainDT <- data.table(val = gainVals)
gainDT[, cumulative_p := gammaCdf(val, gainShape, gainScale)]
gainDT[, p := shift(cumulative_p, type = "lead") - cumulative_p]
stopifnot(round(sum(gainDT$p, na.rm = TRUE), 2) == 1)

# joint gamma probabilities of biases and gains
getJointP <- function(dt) {
  stopifnot(nrow(dt) ==  1)
  
  biasDT[val == dt$bias]$p * gainDT[val == dt$gain]$p
}
grid <- grid[, .(bias, gain, jointP = getJointP(.SD)), by = row.names(grid)]

# make sure the discrete approximation grid covers about all of the original continuous density, up to 2 decimal places
stopifnot(round(sum(grid$jointP, na.rm = TRUE), 2) == 1)

# final normalization to make sure everything sums up to 1
grid$jointP <- grid$jointP/sum(grid$jointP, na.rm = TRUE)
stopifnot(round(sum(grid$jointP, na.rm = TRUE), 2) == 1)

# remove RHS endpoint of last bin and check num rows is correct
grid <- grid[!is.na(jointP)]
stopifnot(nrow(grid) == (length(biasVals)-1)*(length(gainVals)-1))

grid[, row.names := NULL]

biasPlot <- ggplot(data.table(p = dgamma(biasVals, biasShape, scale=biasScale), bias = biasVals), aes(x = bias, y = p)) +
  geom_col() +
  ggtitle(sprintf("shape=%.2f, scale=%.2f, mean=%.2f", biasShape, biasScale, biasShape*biasScale)) +
  theme_mine() +
  theme(plot.title = element_text(size=7))
    
gainPlot <- ggplot(data.table(p = dgamma(gainVals, gainShape, scale=gainScale), gain = gainVals), aes(x = gain, y = p)) +
  geom_col() +
  ggtitle(sprintf("shape=%.2f, scale=%.2f, mean=%.2f", gainShape, gainScale, gainShape*gainScale)) +
  theme_mine() +
  theme(plot.title = element_text(size=7))

biasGainPlots <- plot_grid(biasPlot, gainPlot, ncol = 2)
bgpPlot <- plotBgp(grid)
plot_grid(biasGainPlots, bgpPlot, nrow = 2, rel_heights = c(1, 2)) %>% print()

if (saveGrid) {
  fwrite(grid, file = savePath)
  print(sprintf("Saved to %s!", savePath))
}