library(data.table)
library(magrittr)

# bias: gamma mean at 5*0.1=0.5
biasShape <- 5
biasScale <- 0.1
xs <- seq(0, 3, 0.15)
dgamma(xs, biasShape, scale=biasScale) %>% plot(x = xs)

# gain: gamma mean at 100*0.1=10
gainShape <- 100
gainScale <- 0.1
xs <- seq(0, 20, 0.1)
dgamma(xs, gainShape, scale=gainScale) %>% plot(x = xs)

biasVals <- seq(0, 3, 0.15)
gainVals <- seq(0, 20, 1)
grid <- expand.grid(biasVals, gainVals) %>% as.data.table()
setnames(grid, colnames(grid), c("bias", "gain"))

gammaCdf <- function(x, shape, scale) {
  pgamma(x, shape, scale = scale)
}

# use the cdf to calculate the probability for each bin (represented by the leftmost value, e.g. 0 represents the 0-1 bin for gain)
biasDT <- data.table(val = biasVals)
biasDT[, cumulative_p := gammaCdf(val, biasShape, biasScale)]
biasDT[, p := shift(cumulative_p, type = "lead") - cumulative_p]
stopifnot(round(sum(biasDT$p, na.rm = TRUE), 3) == 1)

gainDT <- data.table(val = gainVals)
gainDT[, cumulative_p := gammaCdf(val, gainShape, gainScale)]
gainDT[, p := shift(cumulative_p, type = "lead") - cumulative_p]
stopifnot(round(sum(gainDT$p, na.rm = TRUE), 3) == 1)

# joint gamma probabilities of biases and gains
getJointP <- function(dt) {
  stopifnot(nrow(dt) ==  1)
  
  biasDT[val == dt$bias]$p * gainDT[val == dt$gain]$p
}
grid <- grid[, .(bias, gain, jointP = getJointP(.SD)), by = row.names(grid)]

# make sure the discrete approximation grid covers about all of the original continuous density, up to 3 decimal places
stopifnot(round(sum(grid$jointP, na.rm = TRUE), 3) == 1)

# final normalization to make sure everything sums up to exactly 1
grid$jointP <- grid$jointP/sum(grid$jointP, na.rm = TRUE)
stopifnot(sum(grid$jointP, na.rm = TRUE) == 1)

# remove RHS endpoint of last bin
grid <- grid[!is.na(jointP)]

grid[, row.names := NULL]
savePath <- sprintf("cache/bias-shape=%i-scale=%.2f_gain-shape=%i-scale=%.2f_grid.csv", biasShape, biasScale, gainShape, gainScale)
fwrite(grid, file = savePath)
print(sprintf("Saved to %s!", savePath))