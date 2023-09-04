source("../plots_and_stats/plotting_helperfuns.R")

createDirs <- function(dirpath) {
  # recursively create the directories if they don't already exist
  
  if (!dir.exists(dirpath)) {
    dir.create(dirpath, recursive = TRUE)
  }
}

# save DTs and print message
saveDT <- function(DT, dirpath, filename) {
  createDirs(dirpath)
  fullPath <- file.path(dirpath, filename)
  fwrite(DT, fullPath)
  print(sprintf("Saved to %s!", fullPath))
}

softmax <- function(vec, temperature) {
  beta <- 1/temperature
  numerators = exp(vec*beta)
  denom = sum(numerators)
  numerators/denom
}
# softmax(c(0, 10), 100)
# 0.4750208 0.5249792

weightedSoftmax <- function(vec, temperature, randP, epsilon) {
  stopifnot(epsilon >= 0 && epsilon <= 1)
  epsilon*randP + (1-epsilon)*softmax(vec, temperature)
}

weightedAdd <- function(vec1, vec2, weight1) {
  stopifnot(length(vec1) == length(vec2))
  stopifnot(weight1 >= 0 && weight1 <= 1)
  
  weight1*vec1 + (1-weight1)*vec2
}
# weightedAdd(c(1, 10), c(10, 100), 0.1)
# 9.1 91

idColsToStr <- function(resultsDT, ids) {
  idCols <- sapply(ids, function(x) paste0("id_", x))
  strCols <- sapply(ids, function(x) paste0("str_", x))
  dt <- resultsDT[, ..idCols]
  
  for (i in 1:length(ids)) {
    dt[, (strCols[i]) := ""]
    dt[dt[[idCols[i]]] == 1, (strCols[i]) := as.character(ids[i])]
    dt[, (idCols[i]) := NULL]  # remove original column
  }
  
  apply(dt, 1, paste0, collapse="")
}

se <- function(x) sd(x, na.rm = TRUE)/sqrt(length(x))

getBgpFromCurrResults <- function(atoms_var) {
  # extract a data.table of bias, gain and their jointP from a scala Map stored under the name in atoms_var
  
  s + 'var tempKeys = Array.empty[Fform]'
  bgs <- s * sprintf('
    tempKeys = %s.keys.toArray
    tempKeys.map(_.name)
    ', atoms_var)
  ps <- s * sprintf('
   tempKeys.map(%s(_))
  ', atoms_var)
  
  bgpDT <- data.table(bg=bgs, jointP=ps)
  bgpDT[, c("bias", "gain") := tstrsplit(bg, ", ")]  # https://stackoverflow.com/questions/18154556/split-text-string-in-a-data-table-columns
  bgpDT[, bg := NULL]
  bgpDT[, bias := as.numeric(bias)]
  bgpDT[, gain := as.numeric(gain)]
  bgpDT[, jointP := as.numeric(jointP)]
  setorder(bgpDT, bias, gain)
  
  bgpDT
}

sigmoid <- function(n, b, g) {
  1/(1 + exp(-g * (n-b)))
}

plotBgp <- function(bgpDT) {
  # plot contour of joint bias gain distribution and samples of sigmoid lines from that distribution
  
  # plot filled contour of joint space
  p <- ggplot(bgpDT, aes(bias, gain, z=jointP)) +
    geom_contour_filled(show.legend = FALSE) +
    theme_mine() +
    theme(panel.grid.major.x = element_line( size=.3, color="light gray"))
  
  # plot samples of joint space
  gridDexes <- 1:nrow(bgpDT)
  dexSamples <- sample(gridDexes, 1000, prob = bgpDT$jointP, replace = TRUE)
  gridSamples <- bgpDT[dexSamples]
  gridSamples[, N := .N, by = c("bias", "gain")]
  # gridSamplesP <- ggplot(data = gridSamples) + geom_contour_filled(aes(x = bias, y = gain, z = N))
  
  # marginal of samples:
  # sampleMarginalB <- gridSamples[, .(margN = sum(N)), by=bias]
  # sampleMarginalG <- gridSamples[, .(margN = sum(N)), by=gain]
  # ggplot() + geom_col(aes(x = sampleMarginalB$bias, y = sampleMarginalB$margN))
  # ggplot() + geom_col(aes(x = sampleMarginalG$gain, y = sampleMarginalG$margN))
  
  # sigmoid function over 0-3 blickets
  ns <- 0:3
  getActivationDT <- function(dt) {
    stopifnot(nrow(dt) == 1)
    ys = sapply(ns, function(x) sigmoid(x, dt$bias, dt$gain))
    data.table(ns, ys)
  }
  
  allLines <- gridSamples[, getActivationDT(.SD), by=rownames(gridSamples)]
  allLinesP <- ggplot(allLines, aes(x = ns, y = ys, group = rownames)) +
    geom_line(alpha = 0.1) +
    theme_mine() + 
    theme(panel.grid.major.x = element_line( size=.3, color="light gray"))
  
  # then combine with the top row for final plot
  finalPlot <- plot_grid(p, allLinesP, ncol = 2)
  finalPlot
}


load_fits <- function(path, modelName) {
  # load an RData file containing fits (of softmax temp and struct vs form weights)
  
  local({
    load(path)  # should put the `fits` var into this isolated local env
    means <- lapply(fits, function(sess) mean(unlist(lapply(sess, function(fold) fold$testMarginalMeanPredLik))))
    meanDT <- data.table(session_id = names(means), mean = means)
    meanDT[, model := modelName]
    
    trainFits <- lapply(fits, function(sess) rbindlist(lapply(sess, function(fold) fold$bestTrainFit)))
    trainFitDT <- rbindlist(trainFits, idcol = "session_id")
    trainFitDT[, model := modelName]
    
    return(list(meanDT, trainFitDT))
  })
}