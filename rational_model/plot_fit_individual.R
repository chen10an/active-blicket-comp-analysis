library(data.table)
library(magrittr)
source("helperfuns.R")

files <- c(main = "cache/2022-04-18_main/fits_allTestPredLikPerInt_useStructEIG=FALSE_normalize=TRUE_individuals/all.RData",
           noP1 = "cache/2022-04-18_noP1/fits_allTestPredLikPerInt_useStructEIG=FALSE_normalize=TRUE_individuals/all.RData",
           noInfo = "cache/2022-04-18_main/fits_allTestPredLikPerInt_useStructEIG=TRUE_normalize=TRUE_individuals/all.RData",
           noSig1 = "cache/2022-04-08_noSig-1/fits_allTestPredLikPerInt_useStructEIG=FALSE_normalize=TRUE_individuals/all.RData")

bestDT <- getBestModelDT(files)

bestDT[, bestModel := factor(bestModel, levels=c("HBM", "No-Transfer", "Structure-Only-EIG", "Fixed-Form", "Random"))]

p <- ggplot(bestDT, aes(x=bestModel, fill=bestModel)) +
  scale_fill_manual(values=c(brewer.pal(n = 8, "Dark2")[1:4], myGray)) +
  geom_histogram(stat="count") +
  geom_text(aes(label = ..count..), stat = "count", vjust = 1.5, color = "white", size = 2.5) +
  xlab("Model") +
  ylab("Number of participants") +
  guides(fill="none") +
  theme_mine() +
  theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust = 1))
print(p)

# save_plot(filename = "../../../Dropbox/drafts/2021-Feb_active_overhypo_modeling/imgs/model_comparison_ind.pdf", plot = p, base_height = NULL, base_width = 2.5, base_asp = 0.7)
