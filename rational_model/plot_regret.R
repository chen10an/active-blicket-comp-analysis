# plot the distribution of form vs struct weight for participants best-fitted by the main HBM model

library(data.table)
library(magrittr)
library(progress)
source("helperfuns.R")

files <- c(main = "cache/2022-04-18_main/fits_allTestPredLikPerInt_useStructEIG=FALSE_individuals/all.RData",
           noP1 = "cache/2022-04-18_noP1/fits_allTestPredLikPerInt_useStructEIG=FALSE_individuals/all.RData",
           noInfo = "cache/2022-04-18_main/fits_allTestPredLikPerInt_useStructEIG=TRUE_individuals/all.RData",
           noSig1 = "cache/2022-04-08_noSig-1/fits_allTestPredLikPerInt_useStructEIG=FALSE_individuals/all.RData")

bestDT <- getBestModelDT(files)

# isolate participants who were best fit by HBM
mainDT <- bestDT[bestModel == "HBM"]

mainDir <- files['main'] %>% dirname() %>% dirname()
PRIORDIRS <- list.dirs(mainDir)
# exclude parent dir
PRIORDIRS <- PRIORDIRS[2:length(PRIORDIRS)]
# exclude folders containing fits
PRIORDIRS <- PRIORDIRS[!grepl("fits", PRIORDIRS)]
stopifnot(length(PRIORDIRS) == 24)  # should be 24 priors

# put all prior-participant data into a list
pb <- progress_bar$new(total = length(mainDT$session_id))
sessToPriorToModelRes <- list()
for (sess in mainDT$session_id) {
  pb$tick()
  priorToModelRes <- lapply(PRIORDIRS, function(dir) fread(file.path(dir, sprintf("%s_2.csv", sess)), colClasses=c(possIntervention="character")))
  names(priorToModelRes) <- PRIORDIRS
  stopifnot(length(priorToModelRes) == length(PRIORDIRS))
  
  sessToPriorToModelRes[[sess]] <- priorToModelRes 
}

pb <- progress_bar$new(total = length(mainDT$session_id))
sessRegrets <- list()
for (sess in mainDT$session_id) {
  pb$tick()
  priorRegrets <- list()
  for (priordir in PRIORDIRS) {
    sessDT <- sessToPriorToModelRes[[sess]][[priordir]]
    
    # collapse id columns into one sorted (low to high id) string that can be compared with possibleInterventions
    sessDT[, actualIntervention := idColsToStr(sessDT, 0:5)]
    
    actualDT <- sessDT[possIntervention == actualIntervention, .(formEIG, structEIG), by = nthIntervention]
    bestDT <- sessDT[, .(formEIG = max(formEIG), structEIG = max(structEIG)), by = nthIntervention]
    worstDT <- sessDT[, .(formEIG = min(formEIG), structEIG = min(structEIG)), by = nthIntervention]
    
    # should be same length as num intervention in phase 
    stopifnot(nrow(actualDT) == 20)
    stopifnot(nrow(bestDT) == 20)
    stopifnot(nrow(worstDT) == 20)
    
    # make sure everything is ordered by nthIntervention
    setorder(actualDT, nthIntervention)
    setorder(bestDT, nthIntervention)
    setorder(worstDT, nthIntervention)
    
    # normalize wrt the maximum and minimum possible eig at each intervention index
    # so that form and structure EIG differences (to the max) are put on the same scale
    # i.e., 0-1 relative to the max and min eig
    normalize <- function(eigs, maxes, mins) {(eigs - mins)/(maxes-mins)}
    loss <- function(eigs) {-eigs}
    
    
    actualDT[, c("formLoss", "structLoss") := list(loss(normalize(formEIG, bestDT$formEIG, worstDT$formEIG)), loss(normalize(structEIG, bestDT$structEIG, worstDT$structEIG)))]
    bestDT[, c("formLoss", "structLoss") := list(loss(normalize(formEIG, formEIG, worstDT$formEIG)), loss(normalize(structEIG, structEIG, worstDT$structEIG)))]
    
    # compute running mean of the loss, i.e., the mean at time t should include all
    # losses from time 0 to t
    running_windows <- seq(max(actualDT$nthIntervention))
    actualDT[, c("runningFormLoss", "runningStructLoss") := list(frollmean(formLoss, running_windows, adaptive = TRUE), frollmean(structLoss, running_windows, adaptive = TRUE))]
    bestDT[, c("runningFormLoss", "runningStructLoss") := list(frollmean(formLoss, running_windows, adaptive = TRUE), frollmean(structLoss, running_windows, adaptive = TRUE))]
    
    # now compute regret
    actualDT[, c("formRegret", "structRegret") := list(runningFormLoss - bestDT$runningFormLoss, runningStructLoss - bestDT$runningStructLoss)]
    
    priorRegrets[[priordir]] <- actualDT
  }
  
  sessRegretDT <- rbindlist(priorRegrets)
  stopifnot(nrow(sessRegretDT) == 20 * 24)  # 20 interventions, 24 priors
  
  # marginalize over all priors assuming uniform distribution over priors
  sessRegretDT <- sessRegretDT[, .(formRegret = mean(formRegret), structRegret = mean(structRegret)), by = nthIntervention]
  
  sessRegrets[[sess]] <- sessRegretDT
}

regretDT <- rbindlist(sessRegrets, idcol = "session_id")
stopifnot(nrow(regretDT) == length(mainDT$session_id) * 20)  # num participants * num interventions

# first compute mean and se across all participants then plot
meanRegretDT <- regretDT[, .(formRegretMean = mean(formRegret), formRegretSE = se(formRegret), structRegretMean = mean(structRegret), structRegretSE = se(structRegret)), by = nthIntervention]
  
p <- ggplot(meanRegretDT, aes(x = nthIntervention)) +
  geom_line(aes(y = (1 - formRegretMean), color = "Overhypothesis")) +
  geom_ribbon(aes(ymin = (1 - formRegretMean) - formRegretSE, ymax = (1 - formRegretMean) + formRegretSE, fill = "Overhypothesis"), alpha = 0.3) +
  geom_line(aes(y = (1 - structRegretMean), color = "Causal Structure")) +
  geom_ribbon(aes(ymin = (1 - structRegretMean) - structRegretSE, ymax = (1 - structRegretMean) + structRegretSE, fill = "Causal Structure"), alpha = 0.3) +
  scale_color_manual(
    name = "Information Type",
    breaks = c("Overhypothesis", "Causal Structure"),
    values = c(myColors[1], myColors[2])) +
  scale_fill_manual(
    name = "Information Type",
    breaks = c("Overhypothesis", "Causal Structure"),
    values = c(myColors[1], myColors[2])) +
  theme_mine() +
  xlab("Intervention") +
  ylab("Closeness to Max. EIG\n(1 - Mean Regret)") +
  ylim(c(0,1))

p

# save_plot(filename = "../../../Dropbox/drafts/2021-Feb_active_overhypo_modeling/imgs/regret.pdf", plot = p, base_height = NULL, base_width = 5, base_asp = 2)

