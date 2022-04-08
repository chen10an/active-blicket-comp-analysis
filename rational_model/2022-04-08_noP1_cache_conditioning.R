# This script caches intermediate data from the scala model. The goal is to use the cached data for fitting parameters on related to EIG (i.e., softmax, weights, ...): given the same participant interventions from the same starting prior distribution, the Bayesian updates and intermediate distributions are exactly the same across different EIG-related parameter values. EIG-related parameters only influences how the model assigns predictive likelihoods to participant interventions but not how it updates from a fixed set of participant interventions.

library(data.table)
library(magrittr)
library(ggplot2)
library(rscala)
library(progress)
library(optparse)
source("helperfuns.R")

parser <- OptionParser()
parser <- add_option(parser, c("-i", "--interventions_dir"), type="character", default="../ignore/output/v2/", 
                     help="Directory with preprocessed interventions data [default %default]")
parser <- add_option(parser, c("-c", "--cache_dir"), type="character", default="cache", 
                     help="Directory with cached output. Don't use a slash at the end (for the sake of correct rsync syntax) [default %default]")
parser <- add_option(parser, c("-r", "--rsync_dest_cache_dir"), type="character", default=NULL, help="Destination directory for periodically calling rsync, where the source directory is in --cache_dir. If null, rsync is not called. Don't use a slash at the end (for the sake of correct rsync syntax) [default %default]")

                    
args <- parse_args(parser)

s <- scala(JARs = "~/projects/active-overhypo-learner/target/scala-2.13/active-overhypothesis-learner_2.13-0.0.0.jar")
s + '
import utils._
import learner._
'

# SET THESE VARS -----
SAVEDIR <- file.path(args$cache_dir, "2022-04-08_noP1") # main model starting from phase 2
createDirs(SAVEDIR)

# sigmoid grid:
grid <- fread(file.path(args$cache_dir, "bias-shape=5-scale=0.10_gain-shape=100-scale=0.10_grid.csv"))  # bin size 0.15
s + '
// create a lookup table for the joint gamma densities of biases and gains
var bgToP = Map.empty[(Double, Double),Double]
'
s(grid = as.matrix(grid)) * '
bgToP = grid.map(arr => (arr(0), arr(1)) -> arr(2)).toMap
'

# prior and model choice:
getModelInitStr <- function(prior_str) {
  # this phase 1 model init will be called for every participant
  
  # main model
  sprintf('new PhaseLearner(%s) with point15FformBinSize', prior_str)  # note the 0.15 bin size to match the grid
}
s + '
val blocksMap = Map[Int, Set[Block]](
 1 -> Set("0", "1", "2").map(Block(_)),
 2 -> Set("0", "1", "2", "3", "4", "5").map(Block(_)),
 3 -> Set("0", "1", "2", "3", "4", "5", "6", "7", "8").map(Block(_))
)
 
// choice of phase TWO prior, which will be reused to initialize a phase TWO learner for each participant
val prior1 = PriorMaker.makeSigmoidPrior(bgToP, blocksMap(2), false)
'

# participant data:
phaseDT <- list(fread(file = file.path(args$interventions_dir, 'interventions1.csv')),
                fread(file = file.path(args$interventions_dir, 'interventions2.csv')))

stopifnot(setequal(unique(phaseDT[[1]]$session_id), unique(phaseDT[[2]]$session_id)))

allParticipants <- unique(phaseDT[[2]]$session_id)
isCached <- sapply(allParticipants, function(sess) file.exists(file.path(SAVEDIR, sprintf("%s_2.csv", sess))))  # already has their phase 2 cached

notCachedSess <- allParticipants[!isCached]  # participants who still need to be cached

# filter out those who have already been cached
phaseDT[[1]] <- phaseDT[[1]][session_id %in% notCachedSess]
phaseDT[[2]] <- phaseDT[[2]][session_id %in% notCachedSess]

for (i in 1:length(phaseDT)) {
  phaseDT[[i]]$timestamp = as.POSIXct(phaseDT[[i]]$timestamp/1000, origin="1970-01-01") 
  phaseDT[[i]][, nthIntervention := rowid(session_id)]
}

s + sprintf('
// vars for updating in place
var currLearner = %s
var currEvents:Vector[Event] = Vector.empty[Event]

var currResults: (Array[(Array[Double], Array[Double], Double, Double, Double, Map[Fform, Double], Map[Set[Block], Double], Map[Hyp, Double], Array[Double])], Array[Set[Block]], Dist[Hyp]) = (Array((Array.empty[Double], Array.empty[Double], Double.NaN, Double.NaN, Double.NaN, Map.empty[Fform, Double], Map.empty[Set[Block], Double], Map.empty[Hyp, Double], Array.empty[Double])), Array.empty[Set[Block]], currLearner.hypsDist)
', getModelInitStr("prior1"))

allSess <- unique(phaseDT[[1]]$session_id)

pb <- progress_bar$new(
  format = "  caching [:bar] :percent eta: :eta",
  total = length(allSess), clear = FALSE, width= 60, show_after = 0)

for (i in 1:length(allSess)) {
  sess <- allSess[i]
  print(sess)
  # pb$message(sess)  # force progress bar to print, esp for slurm log, with info about current sess
  pb$tick()
  
  if (!is.null(args$rsync_dest_cache_dir) && (i == 1 || i %% 20 == 0)) {
    # perform an rsync at the first iteration just as sanity check that it's working
    
    command <- sprintf("rsync --archive --update --compress --progress %s/ %s", args$cache_dir, args$rsync_dest_cache_dir)
    print(sprintf("Performing periodic rsync: %s", command))
    system(command)
  }
  
  # initialize for phase 1
  s * sprintf('currLearner = %s', getModelInitStr("prior1"))
  
  # for (phase in c(1, 2)) {
  for (phase in c(2)) {  # TWO ONLY
    
    # THEN RUN THE REST -----
    dt <- phaseDT[[phase]][session_id == sess]
    
    dtList <- list()
    counter <- 1
    
    allIdCols <- s * 'currLearner.allBlocks.map("id_" + _.name).toArray'
    allIdCols <- sort(allIdCols)
    possibleAllIdCols <- sapply(allIdCols, function(x) paste0("poss_", x))
    
    rInterventions <- dt[, ..allIdCols] %>% as.matrix()
    rOutcomes <- dt[, outcome]  # same order as interventions
    
    # turn into scala style Events
    s (rInterventions, rOutcomes) * '
  val interventions: Array[Set[Block]] = rInterventions.map(_.zipWithIndex.filter{case(state, i) => state==1}.map{case(state, i) => Block(i.toString)}.toSet)
  val outcomes = rOutcomes
  
  assert(interventions.length == outcomes.length)
  
  currEvents = interventions.zipWithIndex.map{case(combo, i) => Event(combo, outcomes(i))}.toVector
  
  currResults = Conditioner.getPhaseResults(currLearner, currEvents)
'
    
    # s * 'currEvents.foreach(print(_))'
    
    possibleInterventions <- s * 'currResults._2.map(_.map(_.name).toVector.sorted.mkString)'  # combo at index i corresponds to column i of the raw EIG matrices that come out of scala
    fEIGMat <- (s * 'currResults._1.map(_._1)') %>% as.data.table()
    setnames(fEIGMat, possibleInterventions)
    fEIGMat[, nthIntervention := dt$nthIntervention]
    fEIGMat <- melt(fEIGMat, id.vars = "nthIntervention", variable.name = "possIntervention", value.name = "formEIG")
    setkey(fEIGMat, nthIntervention, possIntervention)
    
    sEIGMat <- (s * 'currResults._1.map(_._2)') %>% as.data.table()
    setnames(sEIGMat, possibleInterventions)
    sEIGMat[, nthIntervention := dt$nthIntervention]
    sEIGMat <- melt(sEIGMat, id.vars = "nthIntervention", variable.name = "possIntervention", value.name = "structEIG")
    setkey(sEIGMat, nthIntervention, possIntervention)
    
    jEIGMat <- (s * 'currResults._1.map(_._9)') %>% as.data.table()
    setnames(jEIGMat, possibleInterventions)
    jEIGMat[, nthIntervention := dt$nthIntervention]
    jEIGMat <- melt(jEIGMat, id.vars = "nthIntervention", variable.name = "possIntervention", value.name = "jointEIG")
    setkey(jEIGMat, nthIntervention, possIntervention)
    
    # join and check number of rows (num phase interventions x num possible intervention):
    stopifnot(length(unique(c(nrow(fEIGMat), nrow(sEIGMat), nrow(jEIGMat)))) == 1)
    joinedMat <- sEIGMat[fEIGMat]
    joinedMat <- jEIGMat[joinedMat]
    # check all still have the same number of rows
    stopifnot(length(unique(c(nrow(joinedMat), nrow(fEIGMat), nrow(sEIGMat), nrow(jEIGMat)))) == 1)
    
    setkey(joinedMat, nthIntervention)  # to join with per intervention metrics below
    
    fHVec <- s * 'currResults._1.map(_._3)'
    sHVec <-s * 'currResults._1.map(_._4)'
    jointHVec <- s * 'currResults._1.map(_._5)'
    fAVec <- s * 'currResults._1.map(_._6.map{case (fform, p) => fform.name}.mkString(" | "))'
    sAVec <- s * 'currResults._1.map(_._7.map{case (blickets, p) => blickets.map(_.name).toVector.sorted.mkString}.mkString(" | "))'
    jointAVec <- s * 'currResults._1.map(_._8.map{case(hyp, p) => hyp.blickets.map(_.name).toVector.sorted.mkString + "_" + hyp.fform.name}.mkString(" | "))'
    
    # metrics that only have a single value per intervention
    perInterventionDT <- data.table(
      nthIntervention = dt$nthIntervention,
      formEntropy = fHVec,
      structEntropy = sHVec,
      jointEntropy = jointHVec,
      formMax = fAVec,
      structMax = sAVec,
      jointMax = jointAVec
    )
    setkey(perInterventionDT, nthIntervention)
    
    resultsDT <- perInterventionDT[joinedMat]
    setkey(resultsDT, nthIntervention)
    setkey(dt, nthIntervention)
    dtCols <- c(c("session_id", "phase", "nthIntervention", "outcome"),allIdCols)
    resultsDT <- resultsDT[dt[, ..dtCols]]
    stopifnot(nrow(resultsDT) == nrow(joinedMat))
    
    # save per participant per phase
    saveFile <- sprintf("%s_%s.csv", dt$session_id[1], phase)
    fwrite(resultsDT, file.path(SAVEDIR, saveFile))
    
    if (phase == 1) {
      # prepare for the second phase
      s * sprintf('
    val resLearner = %s  // use most up-to-date hypsDist to make a learner with the same assumptions/mixins as currLearner
    
    currLearner = resLearner.transfer(blocksMap(2))  // ready for conditioning on data for phase 2
  ', getModelInitStr("currResults._3"))
    }
  }
}

