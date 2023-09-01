library(data.table)
library(magrittr)
source("helperfuns.R")
set.seed(0) # reproducible participant shuffling

# SET THESE VARS -----
SAMPLESIZE <- 250
NFOLDS <- 4

SAVEDIR <- "cache"
createDirs(SAVEDIR)
SAVEFILE <- "4folds_250.RData"

# RUN -----
# represent each participant with an index
participantDex <- 1:SAMPLESIZE  # full sample size
shuffledDex <- sample(participantDex)

# split the shuffled indices into 5 balanced folds
remainderSize <- mod(SAMPLESIZE,NFOLDS)
noRemainderSize <- SAMPLESIZE - remainderSize
# split noRemainderSize evenly
folds <- list()
for (i in 1:NFOLDS) {
  folds[[i]] <- shuffledDex[((i-1)*(noRemainderSize/NFOLDS) + 1) : (i*(noRemainderSize/NFOLDS))]
}
# then distribute the rest of the remainder
if (remainderSize > 0) {
  for (i in 1:remainderSize) {
    folds[[i]] <- c(folds[[i]], shuffledDex[noRemainderSize+i])
  }
}

stopifnot(sum(sapply(folds, length)) == SAMPLESIZE)
stopifnot(length(unique(unlist(folds))) == SAMPLESIZE)

save(folds, file=file.path(SAVEDIR, SAVEFILE))
print(sprintf("Saved %i folds of %i participants to %s!", NFOLDS, SAMPLESIZE, file.path(SAVEDIR, SAVEFILE)))