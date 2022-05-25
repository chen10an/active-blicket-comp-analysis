library(data.table)
library(magrittr)
library(ggplot2)
source("../plots_and_stats/plotting_helperfuns.R")
source("helperfuns.R")


load("cache/2022-04-18_main/fits_allTestPredLikPerInt_useStructEIG=FALSE_4folds.RData")
mainFits <- fits
# mean testMarginalMeanPredLik over all folds for each participant
mainDT <- data.table(model = "main", predLik = unlist(lapply(mainFits, function(fold) fold$testMarginalMeanPredLik)))

load("cache/2022-04-18_noP1/fits_allTestPredLikPerInt_useStructEIG=FALSE_4folds.RData")
noP1Fits <- fits
# mean testMarginalMeanPredLik over all folds for each participant
noP1DT <- data.table(model = "noP1", predLik = unlist(lapply(noP1Fits, function(fold) fold$testMarginalMeanPredLik)))

load("cache/2022-04-18_main/fits_allTestPredLikPerInt_useStructEIG=TRUE_4folds.RData")
noInfoFits <- fits
# mean testMarginalMeanPredLik over all folds for each participant
noInfoDT <- data.table(model = "noInfo", predLik = unlist(lapply(noInfoFits, function(fold) fold$testMarginalMeanPredLik)))

load("cache/2022-04-08_noSig-1/fits_allTestPredLikPerInt_useStructEIG=FALSE_4folds.RData")
noSig1Fits <- fits
# mean testMarginalMeanPredLik over all folds for each participant
noSig1DT <- data.table(model = "noSig1", predLik = unlist(lapply(noSig1Fits, function(fold) fold$testMarginalMeanPredLik)))

randomDT <- data.table(model = "random", predLik = 1/64)
  
compareDT <- rbind(mainDT, noP1DT, noInfoDT, noSig1DT, randomDT)
compareDT[, .(mean = mean(predLik), se = se(predLik)), by = model]
