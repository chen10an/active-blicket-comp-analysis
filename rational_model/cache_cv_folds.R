library(data.table)
library(magrittr)
source("helperfuns.R")
set.seed(0) # reproducible participant shuffling

# SET THESE VARS -----
SAMPLESIZE <- 240
NFOLDS <- 5

SAVEDIR <- "cache"
createDirs(SAVEDIR)
SAVEFILE <- "5folds_240.RData"

# RUN -----
# represent each participant with an index
participantDex <- 1:SAMPLESIZE  # full sample size
shuffledDex <- sample(participantDex)

# split the shuffled indices into 5 balanced folds
folds <- list()
for (i in 1:NFOLDS) {
  folds[[i]] <- shuffledDex[((i-1)*(SAMPLESIZE/NFOLDS) + 1) : (i*(SAMPLESIZE/NFOLDS))]
}

stopifnot(sum(sapply(folds, length)) == SAMPLESIZE)

save(folds, file=file.path(SAVEDIR, SAVEFILE))
print(sprintf("Saved %i folds of %i participants to %s!", NFOLDS, SAMPLESIZE, file.path(SAVEDIR, SAVEFILE)))