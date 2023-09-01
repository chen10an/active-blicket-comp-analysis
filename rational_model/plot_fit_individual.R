library(data.table)
library(magrittr)
source("../plots_and_stats/plotting_helperfuns.R")
source("helperfuns.R")


load("cache/2022-04-18_main/fits_allTestPredLikPerInt_useStructEIG=FALSE_individuals/all.RData")
mainFits <- fits
# mean testMarginalMeanPredLik over all folds for each participant
mainMean <- lapply(mainFits, function(sess) mean(unlist(lapply(sess, function(fold) fold$testMarginalMeanPredLik))))
mainMeanDT <- data.table(session_id = names(mainMean), mean = mainMean)
mainMeanDT[, model := "HBM"]
mainTrainFits <- lapply(mainFits, function(sess) rbindlist(lapply(sess, function(fold) fold$bestTrainFit)))
mainTrainFitDT <- rbindlist(mainTrainFits, idcol = "session_id")
mainTrainFitDT[, model := "HBM"]

load("cache/2022-04-18_noP1/fits_allTestPredLikPerInt_useStructEIG=FALSE_individuals/all.RData")
noP1Fits <- fits
# mean testMarginalMeanPredLik over all folds for each participant
noP1Mean <- lapply(noP1Fits, function(sess) mean(unlist(lapply(sess, function(fold) fold$testMarginalMeanPredLik))))
noP1MeanDT <- data.table(session_id = names(noP1Mean), mean = noP1Mean)
noP1MeanDT[, model := "No-Transfer"]
noP1TrainFits <- lapply(noP1Fits, function(sess) rbindlist(lapply(sess, function(fold) fold$bestTrainFit)))
noP1TrainFitDT <- rbindlist(noP1TrainFits, idcol = "session_id")
noP1TrainFitDT[, model := "No-Transfer"]

load("cache/2022-04-18_main/fits_allTestPredLikPerInt_useStructEIG=TRUE_individuals/all.RData")
noInfoFits <- fits
# mean testMarginalMeanPredLik over all folds for each participant
noInfoMean <- lapply(noInfoFits, function(sess) mean(unlist(lapply(sess, function(fold) fold$testMarginalMeanPredLik))))
noInfoMeanDT <- data.table(session_id = names(noInfoMean), mean = noInfoMean)
noInfoMeanDT[, model := "Structure-Only-EIG"]
noInfoTrainFits <- lapply(noInfoFits, function(sess) rbindlist(lapply(sess, function(fold) fold$bestTrainFit)))
noInfoTrainFitDT <- rbindlist(noInfoTrainFits, idcol = "session_id")
noInfoTrainFitDT[, model := "Structure-Only-EIG"]

load("cache/2022-04-08_noSig-1/fits_allTestPredLikPerInt_useStructEIG=FALSE_individuals/all.RData")
noSig1Fits <- fits
# mean testMarginalMeanPredLik over all folds for each participant
noSig1Mean <- lapply(noSig1Fits, function(sess) mean(unlist(lapply(sess, function(fold) fold$testMarginalMeanPredLik))))
noSig1MeanDT <- data.table(session_id = names(noSig1Mean), mean = noSig1Mean)
noSig1MeanDT[, model := "Fixed-Form"]
noSig1TrainFits <- lapply(noSig1Fits, function(sess) rbindlist(lapply(sess, function(fold) fold$bestTrainFit)))
noSig1TrainFitDT <- rbindlist(noSig1TrainFits, idcol = "session_id")
noSig1TrainFitDT[, model := "Fixed-Form"]

randomDT <- data.table(session_id = mainMeanDT$session_id, mean = 1/64, model = "Random")
  
# OBS: random model comes first so it gets picked when another model (i.e., noSig1) has the same predictive likelihood as the random level
compareDT <- rbind(randomDT, mainMeanDT, noP1MeanDT, noInfoMeanDT, noSig1MeanDT)
paramDT <- rbind(mainTrainFitDT, noP1TrainFitDT, noInfoTrainFitDT, noSig1TrainFitDT)

# compute posterior probabilities of each model p(model | sess), assuming a uniform prior
compareDT[, mean := unlist(mean)]  # list data struct seems to be remaining from fits
compareDT[, posterior := mean/sum(mean), by = session_id]

compareDT[mean == 1/64]$model %>% unique()

bestDT <- compareDT[, .(bestModel = .SD$model[which.max(mean)], bestPosterior = .SD$posterior[which.max(mean)]), by=session_id]
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
