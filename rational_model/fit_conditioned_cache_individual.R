# fit model parameters on all training CV folds and save the results

library(data.table)
library(magrittr)
library(progress)
library(optparse)
source("helperfuns.R")  # contains softmax and weightedAdd functions
set.seed(0) # reproducible shuffling for making cv splitss

parser <- OptionParser()
parser <- add_option(parser, c("-c", "--cache_dir"), type="character", default="~/projects/active-blicket-comp-analysis/rational_model/cache", 
                     help="Directory with cached output. [default %default]")
parser <- add_option(parser, c("-m", "--model_subdir"), type="character", default=NULL, 
                     help="A subdirectory of --cache_dir containing the cached output for a specific model, which should then have subdirectories corresponding to running this model with different priors. Give this subdirectory path relative to --cache_dir [default %default]")
parser <- add_option(parser, c("-s", "--useStructEIG"), action="store_true", default=FALSE, help="Instead of using both form and structure EIG for calculating predictive likelihoods, use only the marginal structure EIG [default %default]")
args <- parse_args(parser)

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

SAVEDIR <- file.path(FULLMODELDIR, sprintf("fits_allTestPredLikPerInt_useStructEIG=%s_individuals", args$useStructEIG))
createDirs(SAVEDIR)

PRIORDIRS <- PRIORDIRS[!grepl("fits_allTestPredLikPerInt_useStructEIG", normalizePath(PRIORDIRS))]  # exclude SAVEDIR

# make an ordered vector of participant session ids, to be indexed by the shuffled indices stored in `folds`
participantDT <- fread(file =  "../ignore/output/v2/interventions2.csv")
orderedParticipants <- participantDT$session_id %>% unique()
# data.table(orderedParticipants) %>% fwrite("cache/orderedParticipants.csv")  # save a record of the order used

createIntFolds <- function(numInt=20, nfolds=4) {
  # return a list that maps fold indices to intervention indices
  
  # return a DT that assigns participants to n folds
  shuffledDex <- sample(1:numInt)
  # split the shuffled participants into 5 balanced folds
  remainderSize <- mod(length(shuffledDex), nfolds)
  noRemainderSize <- length(shuffledDex) - remainderSize
  
  # split noRemainderSize evenly
  folds <- list()
  for (i in 1:nfolds) {
    folds[[i]] <- shuffledDex[((i-1)*(noRemainderSize/nfolds) + 1) : (i*(noRemainderSize/nfolds))]
  }
  # then distribute the rest of the remainder
  if (remainderSize > 0) {
    for (i in 1:remainderSize) {
      folds[[i]] <- c(folds[[i]], shuffledDex[noRemainderSize+i])
    }
  }
  
  stopifnot(sum(sapply(folds, length)) == numInt)
  stopifnot(length(unique(unlist(folds))) == numInt)
  
  folds
}

# RUN -----
# get all cached model results (transfer/2 phase) for participants
print(sprintf("%s: Fitting phase 2 model results to individuals, marginalized over priors.", FULLMODELDIR))

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

pb <- progress_bar$new(
  format = "  fitting [:bar] :percent eta: :eta",
  total = length(orderedParticipants), clear = FALSE, width= 60, show_after = 0)

fits <- list()
for (sess in orderedParticipants) {
  pb$tick()
  folds <- createIntFolds()
  sessFits <- list()
  for (holdout in 1:length(folds)) {
    testIntDex <- folds[[holdout]]
    trainFolds <- sapply(1:length(folds), function(fold) if(fold != holdout) fold else NA)
    trainFolds <- trainFolds[!is.na(trainFolds)]
    trainIntDex <- folds[trainFolds] %>% unlist()
    stopifnot(length(intersect(testIntDex, trainIntDex)) == 0)
    
    # fit parameter grid on train data
    paramFits <- list()  # track mean predictive likelihood for each parameter combination
    for (i in 1:length(STRUCTW_GRID)) {
      structw <- STRUCTW_GRID[i]
      
      for (j in 1:length(TEMPERATURE_GRID)) {
        temp <- TEMPERATURE_GRID[j]
        
        priorFits <- list()
        for (priordir in PRIORDIRS) {
          sessDT <- sessToPriorToModelRes[[sess]][[priordir]]
          trainDT <- sessDT[nthIntervention %in% trainIntDex]
          
          # collapse id columns into one sorted (low to high id) string that can be compared with possibleInterventions
          trainDT[, actualIntervention := idColsToStr(trainDT, 0:5)]
          
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
        
        paramFits[[(i-1)*length(TEMPERATURE_GRID) + j]] <- data.table(temp=temp, structw=structw, marginalMeanPredLik=marginalMeanPredLik)
      }
    }
    
    paramFitDT <- rbindlist(paramFits)
    
    bestFit <- paramFitDT[marginalMeanPredLik == max(marginalMeanPredLik, na.rm = TRUE)]
    
    if (nrow(bestFit) > 1) {  # just choose one of the best fits
      bestFit <- bestFit[1]
    }
    
    # evaluate fitted parameters on test data
    priorTests <- list()
    for (priordir in PRIORDIRS) {
      sessDT <- sessToPriorToModelRes[[sess]][[priordir]]
      testDT <- sessDT[nthIntervention %in% testIntDex]
      # collapse id columns into one sorted (low to high id) string that can be compared with possibleInterventions
      testDT[, actualIntervention := idColsToStr(testDT, 0:5)]
      
      testDT[, addedEIG := weightedAdd(structEIG, formEIG, bestFit$structw)]
      testDT[, predLik := softmax(addedEIG, bestFit$temp), by=.(session_id, nthIntervention)]
      testPredLik <- testDT[actualIntervention == possIntervention, .(mean = mean(predLik, na.rm = TRUE), se = se(predLik))]
      
      priorTests[[priordir]] <- testPredLik
    }
    
    priorTestDT <- rbindlist(priorTests)
    stopifnot(nrow(priorTestDT) == length(PRIORDIRS))
    
    # marginalize over all priors assuming uniform distribution over priors
    testMarginalMeanPredLik <- mean(priorTestDT$mean)
    
    sessFits[[holdout]] <- list(trainFit = paramFitDT, bestTrainFit = bestFit, testMarginalMeanPredLik = testMarginalMeanPredLik)
  }
  
  # intermediate caching
  save(sessFits, file=file.path(SAVEDIR, sprintf("%s.RData", sess)))
  
  fits[[sess]] <- sessFits
}

save(fits, file=file.path(SAVEDIR, "all.RData"))
print(sprintf("Saved all individuals' fits to %s!", file.path(SAVEDIR, "all.RData")))

