# fit model parameters on all training CV folds and save the results

library(data.table)
library(magrittr)
library(progress)
library(optparse)
source("helperfuns.R")  # contains softmax and weightedAdd functions

parser <- OptionParser()
parser <- add_option(parser, c("-c", "--cache_dir"), type="character", default="~/projects/active-blicket-comp-analysis/rational_model/cache", 
                     help="Directory with cached output. [default %default]")
parser <- add_option(parser, c("-m", "--model_subdir"), type="character", default=NULL, 
                     help="A subdirectory of --cache_dir containing the cached output for a specific model, which should then have subdirectories corresponding to running this model with different priors. Give this subdirectory path relative to --cache_dir [default %default]")
parser <- add_option(parser, c("-s", "--useStructEIG"), action="store_true", default=FALSE, help="Instead of using both form and structure EIG for calculating predictive likelihoods, use only the marginal structure EIG [default %default]")
args <- parse_args(parser)

# for testing:
# args <- parse_args(parser, c("-m", "2022-04-18_main"))

# SET VARS -----
if (args$useStructEIG) {
  STRUCTW_GRID <- 1  # represents the noFormEIG ablation
  print("Using struct only EIG")
} else {
  STRUCTW_GRID <- seq(0, 0.9, by=0.1)
  print("Using weighted struct vs form EIG.")
}

TEMPERATURE_GRID <- c(0.001, 0.01, 0.1, 1, 10, 100)
# TEMPERATURE_GRID <- seq(0, 1, by=0.01)

FULLMODELDIR <- file.path(args$cache_dir, args$model_subdir)
if (args$model_subdir == "2022-04-08_noSig-1") {
  # use the model directory itself as the single prior directory because this model has only a single disjunctive-only prior
  PRIORDIRS <- FULLMODELDIR
} else {
  PRIORDIRS <- list.dirs(FULLMODELDIR)
  PRIORDIRS <- PRIORDIRS[2:length(PRIORDIRS)]  # exclude the parent directory itself
}

# folds on participant indices
load("cache/4folds_250.RData")  # variable called `folds`

SAVEPATH <- file.path(FULLMODELDIR, sprintf("fits_allTestPredLikPerInt_useStructEIG=%s_4folds.RData", args$useStructEIG))

PRIORDIRS <- PRIORDIRS[!grepl("fits_allTestPredLikPerInt_useStructEIG", normalizePath(PRIORDIRS))]  # exclude other dirs

# make an ordered vector of participant session ids, to be indexed by the shuffled indices stored in `folds`
participantDT <- fread(file =  "../ignore/output/v2/interventions2.csv")
orderedParticipants <- participantDT$session_id %>% unique()
# data.table(orderedParticipants) %>% fwrite("cache/orderedParticipants.csv")  # save a record of the order used

# RUN -----
# get all cached model results (transfer/2 phase) for participants
print(sprintf("%s: Fitting phase 2 model results.", FULLMODELDIR))

print("Loading in model results for each prior.")
pb <- progress_bar$new(total = length(orderedParticipants))
sessToPriorToModelRes <- list()
for (sess in orderedParticipants) {
  pb$tick()
  priorToModelRes <- lapply(PRIORDIRS, function(dir) fread(file.path(dir, sprintf("%s_2.csv", sess)), colClasses=c(possIntervention="character")))
  names(priorToModelRes) <- PRIORDIRS
  stopifnot(length(priorToModelRes) == length(PRIORDIRS))
  
 sessToPriorToModelRes[[sess]] <- priorToModelRes 
}

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
  
  stopifnot(length(trainSess) > length(testSess))
  stopifnot(length(testSess) + length(trainSess) == 250)
  
  # fit parameter grid on train data
  fitList <- list()  # track mean predictive likelihood for each parameter combination
  for (i in 1:length(STRUCTW_GRID)) {
    structw <- STRUCTW_GRID[i]
    
    for (j in 1:length(TEMPERATURE_GRID)) {
      temp <- TEMPERATURE_GRID[j]
      
      priorFits <- list()
      for (priordir in PRIORDIRS) {
        trainDT <- lapply(sessToPriorToModelRes[trainSess], function(x) x[[priordir]]) %>% rbindlist()
        stopifnot(nrow(trainDT) == length(trainDex)*20*64)
        
        # collapse id columns into one sorted (low to high id) string that can be compared with possibleInterventions
        trainDT[, actualIntervention := idColsToStr(trainDT, 0:5)]
        setorder(trainDT, session_id, nthIntervention, possIntervention)

        toFitDT <- copy(trainDT)
        
        toFitDT[, addedEIG := weightedAdd(structEIG, formEIG, structw)]
        toFitDT[, predLik := softmax(addedEIG, temp), by=.(session_id, nthIntervention)]

        # mean predictive likelihood over all participants' interventions (no grouping, only filtering to get predLik on possIntervention when possIntervention=actualIntervention)
        meanPredLik <- toFitDT[actualIntervention == possIntervention, mean(predLik, na.rm = TRUE)]
        
        priorFits[[priordir]] <- data.table(temp=temp, structw=structw, meanPredLik=meanPredLik)
      }
      
      priorFitDT <- rbindlist(priorFits)
      stopifnot(nrow(priorFitDT) == length(PRIORDIRS))
      
      # marginalize over all priors assuming uniform distribution over priors
      marginalMeanPredLik <- mean(priorFitDT$meanPredLik)
      
      fitList[[(i-1)*length(TEMPERATURE_GRID) + j]] <- data.table(temp=temp, structw=structw, marginalMeanPredLik=marginalMeanPredLik)
    }
  }
  
  fitDT <- rbindlist(fitList)
  
  bestFit <- fitDT[marginalMeanPredLik == max(marginalMeanPredLik, na.rm = TRUE)]
  if (nrow(bestFit) > 1) {  # just choose one of the best fits
    bestFit <- bestFit[1]
  }
  
  # evaluate fitted parameters on test data
  priorTests <- list()
  for (priordir in PRIORDIRS) {
    testDT <- lapply(sessToPriorToModelRes[testSess], function(x) x[[priordir]]) %>% rbindlist()
    stopifnot(nrow(testDT) == length(testDex)*20*64)
    
    # collapse id columns into one sorted (low to high id) string that can be compared with possibleInterventions
    testDT[, actualIntervention := idColsToStr(testDT, 0:5)]
    setorder(testDT, session_id, nthIntervention, possIntervention)
    
    testDT[, addedEIG := weightedAdd(structEIG, formEIG, bestFit$structw)]
    testDT[, predLik := softmax(addedEIG, bestFit$temp), by=.(session_id, nthIntervention)]
    testPredLik <- testDT[actualIntervention == possIntervention, .(mean = mean(predLik, na.rm = TRUE), se = se(predLik))]
    
    priorTests[[priordir]] <- testPredLik
  }
  
  priorTestDT <- rbindlist(priorTests)
  stopifnot(nrow(priorTestDT) == length(PRIORDIRS))
  
  # marginalize over all priors assuming uniform distribution over priors
  testMarginalMeanPredLik <- mean(priorTestDT$mean)
  
  fits[[holdout]] <- list(trainFit = fitDT, bestTrainFit = bestFit, testMarginalMeanPredLik = testMarginalMeanPredLik, testDT = testDT)
}

save(fits, file=SAVEPATH)
print(sprintf("Saved fits to %s!", SAVEPATH))


