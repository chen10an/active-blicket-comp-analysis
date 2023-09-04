library(data.table)
library(magrittr)
source("helperfuns.R")

files <- c(main = "cache/2022-04-18_main/fits_allTestPredLikPerInt_useStructEIG=FALSE_individuals/all.RData",
           noP1 = "cache/2022-04-18_noP1/fits_allTestPredLikPerInt_useStructEIG=FALSE_individuals/all.RData",
           noInfo = "cache/2022-04-18_main/fits_allTestPredLikPerInt_useStructEIG=TRUE_individuals/all.RData",
           noSig1 = "cache/2022-04-08_noSig-1/fits_allTestPredLikPerInt_useStructEIG=FALSE_individuals/all.RData")
modelNames <- c("HBM", "No-Transfer", "Structure-Only-EIG", "Fixed-Form")

# load fits and put the resulting DTs into environment variables
for (i in 1:length(files)) {
  list2env(
    setNames(
      load_fits(files[i], modelNames[i]), 
      c(sprintf("%sMeanDT", names(files)[i]), sprintf("%sTrainFitDT", names(files)[i]))),
    envir = .GlobalEnv)
}

randomDT <- data.table(session_id = mainMeanDT$session_id, mean = 1/64, model = "Random")
  
# OBS: random model comes first so it gets picked when another model (i.e., noSig1) has the same predictive likelihood as the random level
compareDT <- rbind(randomDT, mainMeanDT, noP1MeanDT, noInfoMeanDT, noSig1MeanDT)
paramDT <- rbind(mainTrainFitDT, noP1TrainFitDT, noInfoTrainFitDT, noSig1TrainFitDT)

# compute posterior probabilities of each model p(model | sess), assuming a uniform prior
compareDT[, mean := unlist(mean)]  # list data struct seems to be remaining from fits
compareDT[, posterior := mean/sum(mean), by = session_id]

compareDT[mean == 1/64]$model %>% unique()

bestDT <- compareDT[, .(bestModel = .SD$model[which.max(posterior)], bestPosterior = .SD$posterior[which.max(posterior)]), by=session_id]
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
