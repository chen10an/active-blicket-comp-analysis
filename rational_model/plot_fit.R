library(data.table)
library(magrittr)
library(ggplot2)
source("../plots_and_stats/plotting_helperfuns.R")

load("cache/main_fits_allTestPredLikPerInt.RData")
mainFits <- fits
mainPerInt <- allTestPredLikPerInt

load("cache/main-noFormEIG_fits_allTestPredLikPerInt.RData")
noFormEIGFits <- fits
noFormEIGPerInt <- allTestPredLikPerInt

load("cache/noSig-6_fits_allTestPredLikPerInt.RData")
noSig6Fits <- fits
noSig6PerInt <- allTestPredLikPerInt

load("cache/noSig-1_fits_allTestPredLikPerInt.RData")
noSig1Fits <- fits
noSig1PerInt <- allTestPredLikPerInt

load("cache/noP1_fits_allTestPredLikPerInt.RData")
noP1Fits <- fits
noP1PerInt <- allTestPredLikPerInt

compareDT <- rbindlist(list("HBM"=mainPerInt, "No-info"=noFormEIGPerInt, "No-space-6"=noSig6PerInt, "No-space-1"=noSig1PerInt, "No-reuse"=noP1PerInt), idcol = TRUE)

# compare main model with others
p <- ggplot(compareDT, aes(x = nthIntervention, y=mean, color=.id)) +
  geom_line() +
  geom_errorbar(aes(ymin = mean-se, ymax = mean+se), width = 0.2, linetype="solid") +
  # random baseline
  geom_hline(yintercept=1/64, linetype="dotted", color = "black", size = 1) +
  scale_colour_manual(values=brewer.pal(n = 8, "Dark2"), name = "Model") +
  theme_mine() +
  xlab("Intervention") +
  ylab("Mean predictive likelihood")
p

save_plot(filename = "../../../Dropbox/drafts/2021-Aug_WHY21/imgs/comparison.pdf", plot = p, base_height = NULL, base_width = 8, base_asp = 1.9)

# main model: compare participants to max ------
# ggplot(mainPerInt, aes(x = nthIntervention, y=mean)) +
#   geom_line() +
#   geom_line(aes(y=meanSessMaxPoss)) +
#   geom_errorbar(aes(ymin = mean-se, ymax = mean+se), width = 0.2, linetype="solid") +
#   # random baseline
#   geom_hline(yintercept=1/64, linetype="dotted", color = myGreen, size = 1) +
#   theme_mine() +
#   ggtitle("Main model's mean pred. likelihood vs the max possible")

# ----
# load("cache/main-0.01temps_fits_allTestPredLikPerInt.RData")
# 
# ggplot(testPredLikPerInt, aes(x = nthIntervention, y=mean)) +
#   geom_line() +
#   geom_line(aes(y=meanSessMaxPoss)) +
#   geom_errorbar(aes(ymin = mean-se, ymax = mean+se), width = 0.2, linetype="solid") +
#   # random baseline
#   geom_hline(yintercept=1/64, linetype="dotted", color = myGreen, size = 1) +
#   theme_mine() +
#   ggtitle("Main model's mean pred. likelihood vs the max possible")
