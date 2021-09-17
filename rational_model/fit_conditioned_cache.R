# fit model parameters on all training CV folds and save the results

library(data.table)
library(magrittr)
library(progress)
source("helperfuns.R")  # contains softmax and weightedAdd functions

# SET VARS -----

# TODO: change to form-based weights

# STRUCTW_GRID <- 1  # represents the noFormEIG ablation
STRUCTW_GRID <- seq(0, 0.9, by=0.1)
TEMPERATURE_GRID <- c(0.001, 0.01, 0.1, 1, 10, 100)
# TEMPERATURE_GRID <- seq(0, 1, by=0.01)

MODELDIR <- "cache/noP1"
SAVEPATH <- "cache/noP1_fits_allTestPredLikPerInt.RData"

# folds on participant indices
load("cache/5folds_240.RData")  # variable called `folds`

# TODO: CHANGE TIMESTAMP AFTER I'VE FITTED EVERYONE
# make an ordered vector of participant session ids, to be indexed by the shuffled indices stored in `folds`
participantDT <- fread(file = "../ignore/output/v2/interventions2.csv")
participantDT$timestamp = as.POSIXct(participantDT$timestamp/1000, origin="1970-01-01")
orderedParticipants <- participantDT[timestamp <= "2021-09-15"]$session_id %>% unique()
# data.table(orderedParticipants) %>% fwrite("cache/orderedParticipants.csv")  # save a record of the order used

# RUN -----
# get all cached model results (transfer/2 phase) for participants
sessToModelRes <- lapply(orderedParticipants, function(sess) fread(file.path(MODELDIR, sprintf("%s_2.csv", sess)), colClasses=c(possIntervention="character")))
names(sessToModelRes) <- orderedParticipants

pb <- progress_bar$new(total = length(folds))

fits <- list()
for (holdout in 1:length(folds)) {
  pb$tick()
  
  testDex <- folds[[holdout]]
  testSess <- orderedParticipants[testDex]
  
  trainFolds <- sapply(1:length(folds), function(fold) if(fold != holdout) fold else NA)
  trainFolds <- trainFolds[!is.na(trainFolds)]
  trainDex <- folds[trainFolds] %>% unlist()
  trainSess <- orderedParticipants[trainDex]
  
  if (is.na(testSess) || is.na(trainSess) %>% any()) {
    print("OBS: Not all training and test indices correspond to a participant.")  # this is ok if I haven't finished data collection
    
    trainSess <- trainSess[!is.na(trainSess)]
    testSess <- testSess[!is.na(testSess)]
  }
  
  trainDT <- sessToModelRes[trainSess] %>% rbindlist()
  testDT <- sessToModelRes[testSess] %>% rbindlist()
  
  # collapse id columns into one sorted (low to high id) string that can be compared with possibleInterventions
  trainDT[, actualIntervention := idColsToStr(trainDT, 0:5)]
  setorder(trainDT, session_id, nthIntervention, possIntervention)
  testDT[, actualIntervention := idColsToStr(testDT, 0:5)]
  setorder(testDT, session_id, nthIntervention, possIntervention)
  
  # number of possible interventions; same between train and test
  # numPoss <- trainDT[, .N, by=.(session_id, nthIntervention)]$N %>% unique()
  # stopifnot(numPoss == testDT[, .N, by=.(session_id, nthIntervention)]$N %>% unique())
  
  # fit parameter grid on train data
  fitList <- list()  # track mean predictive likelihood for each parameter combination
  for (i in 1:length(STRUCTW_GRID)) {
    structw <- STRUCTW_GRID[i]
    
    for (j in 1:length(TEMPERATURE_GRID)) {
      temp <- TEMPERATURE_GRID[j]
      
      toFitDT <- copy(trainDT)
      
      toFitDT[, addedEIG := weightedAdd(structEIG, formEIG, structw)]
      toFitDT[, predLik := softmax(addedEIG, temp), by=.(session_id, nthIntervention)]
      
      # no need to shift because the EIGs are already based on the distributions _prior_ to the possible interventions
      
      # # given the above setorder, now we can lag by number of possible interventions to get intervention nth's predictive likelihoods next to the n+1th possible interventions
      # toFitDT[, predLik := shift(likelihood, numPoss, type="lag"), by=session_id]
      
      # mean predictive likelihood over all participants' interventions (no grouping, only filtering to get predLik on possIntervention when possIntervention=actualIntervention)
      meanPredLik <- toFitDT[actualIntervention == possIntervention, mean(predLik, na.rm = TRUE)]
      
      fitList[[(i-1)*length(TEMPERATURE_GRID) + j]] <- data.table(temp=temp, structw=structw, meanPredLik=meanPredLik)
    }
  }
  
  fitDT <- rbindlist(fitList)
  
  bestFit <- fitDT[meanPredLik == max(meanPredLik, na.rm = TRUE)]
  if (nrow(bestFit) > 1) {  # just choose one of the best fits
    bestFit <- bestFit[1]
  }
  
  # evaluate fitted parameters on test data
  testDT[, addedEIG := weightedAdd(structEIG, formEIG, bestFit$structw)]
  testDT[, predLik := softmax(addedEIG, bestFit$temp), by=.(session_id, nthIntervention)]
  # testDT[, predLik := shift(likelihood, numPoss, type="lag"), by=session_id]
  testPredLik <- testDT[actualIntervention == possIntervention, .(mean = mean(predLik, na.rm = TRUE), se = se(predLik))]
  
  # also get mean predictive likelihoods aggregated over participants and grouped by nthIntervention, with standard error
  testPredLikPerInt <- testDT[actualIntervention == possIntervention, .(mean = mean(predLik, na.rm = TRUE), se = se(predLik)), by=nthIntervention]
  
  # and compare with the mean (over participants) max pred likelihood (over all possible interventions)
  testDT[, maxPredLik := max(predLik), by=.(session_id, nthIntervention)]
  testPredLikPerInt[, meanSessMaxPoss := testDT[, mean(maxPredLik, na.rm = TRUE), by=nthIntervention]$V1]
  
  fits[[holdout]] <- list(trainFit = fitDT, bestTrainFit = bestFit, testPredLik = testPredLik, testPredLikPerInt = testPredLikPerInt, testDT = testDT)
}

# aggregated metrics over ALL holdout folds, each parameterized
allTestDT <- lapply(fits, function(x) x[["testDT"]]) %>% rbindlist()
allTestPredLikPerInt <- allTestDT[actualIntervention == possIntervention, .(mean = mean(predLik, na.rm = TRUE), se = se(predLik)), by=nthIntervention]

allTestDT[, maxPredLik := max(predLik), by=.(session_id, nthIntervention)]
allTestPredLikPerInt[, meanSessMaxPoss := allTestDT[, mean(maxPredLik, na.rm = TRUE), by=nthIntervention]$V1]

save(fits, allTestPredLikPerInt, file=SAVEPATH)
print(sprintf("Saved fits to %s!", SAVEPATH))

# fits[[1]]$testPredLikPerInt$mean %>% plot()
# fits[[1]]$testPredLikPerInt$meanSessMaxPoss %>% plot()

