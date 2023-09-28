library(data.table)
library(magrittr)
library(progress)
source("helperfuns.R")

files <- c(main = "cache/2022-04-18_main/fits_allTestPredLikPerInt_useStructEIG=FALSE_normalize=TRUE_individuals/all.RData",
           noP1 = "cache/2022-04-18_noP1/fits_allTestPredLikPerInt_useStructEIG=FALSE_normalize=TRUE_individuals/all.RData",
           noInfo = "cache/2022-04-18_main/fits_allTestPredLikPerInt_useStructEIG=TRUE_normalize=TRUE_individuals/all.RData",
           noSig1 = "cache/2022-04-08_noSig-1/fits_allTestPredLikPerInt_useStructEIG=FALSE_normalize=TRUE_individuals/all.RData")

bestDT <- getBestModelDT(files)

modelNames <- c(
  main = "HBM", 
  noP1 = "No-Transfer", 
  noInfo = "Structure-Only-EIG",
  noSig1 = "Fixed-Form")

params <- lapply(names(files), function(n) loadFits(files[n], modelNames[n])[[2]])
paramDT <- rbindlist(params)

# join paramDT with bestDT such that we get the best structw parameters under the best model per participant
setkey(paramDT, session_id, model)
setkey(bestDT, session_id, bestModel)
bestDT <- paramDT[bestDT]

# 1-structw to get the weight wrt form
bestDT[, fformw := 1-structw]

p <- ggplot(bestDT[model == "HBM"], aes(y=..count../sum(..count..), x=fformw)) +
  geom_histogram(stat="count") +
  xlab("Weight for overhypothesis EIG") +
  ylab("Proportion of participant fits") +
  guides(fill="none") +
  ylim(0, 1) +
  theme_mine()
p

# save_plot(filename = "../../../Dropbox/drafts/2021-Feb_active_overhypo_modeling/imgs/weight_hist.pdf", plot = p, base_height = NULL, base_width = 5, base_asp = 2.4)
