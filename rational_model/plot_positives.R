# plot the distribution of positive outcomes for participants best-fitted by random vs other models

library(data.table)
library(magrittr)
library(progress)
source("helperfuns.R")

files <- c(main = "cache/2022-04-18_main/fits_allTestPredLikPerInt_useStructEIG=FALSE_individuals/all.RData",
           noP1 = "cache/2022-04-18_noP1/fits_allTestPredLikPerInt_useStructEIG=FALSE_individuals/all.RData",
           noInfo = "cache/2022-04-18_main/fits_allTestPredLikPerInt_useStructEIG=TRUE_individuals/all.RData",
           noSig1 = "cache/2022-04-08_noSig-1/fits_allTestPredLikPerInt_useStructEIG=FALSE_individuals/all.RData")

bestDT <- getBestModelDT(files)

outcomeDT <- fread(file = "../ignore/output/v2/interventions2.csv")[, .(session_id, outcome)]

# join with best model label
outcomeDT <- bestDT[outcomeDT, on = "session_id"]

# sum of positive outcomes per participant
outcomeDT <- outcomeDT[, .(numPos = sum(outcome)), by = .(bestModel, session_id)]

# order for plotting
# outcomeDT[, bestModel := factor(bestModel, levels=c("HBM", "No-Transfer", "Structure-Only-EIG", "Fixed-Form", "Random"))]

# group by random vs not random
outcomeDT[bestModel == "Random", bestModelGroup := "Random"]
outcomeDT[bestModel != "Random", bestModelGroup := "HBM and Ablations"]

p <- ggplot(outcomeDT, aes(x=bestModelGroup, y=numPos, fill=bestModelGroup)) +
  geom_boxplot() +
  scale_fill_manual(values=c(brewer.pal(n = 8, "Dark2")[1], myGray)) +
  xlab("Participant's Best Model") +
  ylab("Num. Positives") +
  guides(fill="none") +
  theme_mine() +
  theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust = 1))

# save_plot(filename = "../../../Dropbox/drafts/2021-Feb_active_overhypo_modeling/imgs/positives.pdf", plot = p, base_height = NULL, base_width = 5, base_asp = 2)