# This script caches intermediate data from the scala model. The goal is to use the cached data for fitting parameters on related to EIG (i.e., softmax, weights, ...): given the same participant interventions from the same starting prior distribution, the Bayesian updates and intermediate distributions are exactly the same across different EIG-related parameter values. EIG-related parameters only influences how the model assigns predictive likelihoods to participant interventions but not how it updates from a fixed set of participant interventions.

library(data.table)
library(magrittr)
library(ggplot2)
library(rscala)
library(progress)
source("helperfuns.R")
s <- scala(JARs = "~/projects/active-overhypo-learner/target/scala-2.13/active-overhypothesis-learner_2.13-0.0.0.jar")
s + '
import utils._
import learner._
'

# SET THESE VARS -----
SAVEDIR <- "cache/main"  # main model, no ablations
createDirs(SAVEDIR)

# sigmoid grid:
grid <- fread("cache/bias-shape=5-scale=0.10_gain-shape=100-scale=0.10_grid.csv")
s + '
// create a lookup table for the joint gamma densities of biases and gains
var bgToP = Map.empty[(Double, Double),Double]
'
s(grid = as.matrix(grid)) * '
bgToP = grid.map(arr => (arr(0), arr(1)) -> arr(2)).toMap
'

# prior and model choice:
s + '
val blocksMap = Map[Int, Set[Block]](
 1 -> Set("0", "1", "2").map(Block(_)),
 2 -> Set("0", "1", "2", "3", "4", "5").map(Block(_)),
 3 -> Set("0", "1", "2", "3", "4", "5", "6", "7", "8").map(Block(_))
)
 
// choice of phase 1 prior, which will be reused to initialize a phase 1 learner for each participant
val prior1 = PriorMaker.makeSigmoidPrior(bgToP, blocksMap(1), false)
'

getModelInitStr <- function(prior_str) {
  # this phase 1 model init will be called for every participant
  
  # main model
  sprintf('new PhaseLearner(%s) with point1FformBinSize', prior_str)
}

# participant data:
phaseDT <- list(fread(file = '../ignore/output/v2/interventions1.csv'),
                fread(file = '../ignore/output/v2/interventions2.csv'))

stopifnot(setequal(unique(phaseDT[[1]]$session_id), unique(phaseDT[[2]]$session_id)))

allParticipants <- unique(phaseDT[[2]]$session_id)
isCached <- sapply(allParticipants, function(sess) file.exists(file.path(SAVEDIR, sprintf("%s_2.csv", sess))))  # already has their phase 2 cached

notCachedSess <- allParticipants[!isCached]  # participants who still need to be cached

# filter out those who have already been cached
phaseDT[[1]] <- phaseDT[[1]][session_id %in% notCachedSess]
phaseDT[[2]] <- phaseDT[[2]][session_id %in% notCachedSess]

# THEN RUN THE REST -----

for (i in 1:length(phaseDT)) {
  phaseDT[[i]]$timestamp = as.POSIXct(phaseDT[[i]]$timestamp/1000, origin="1970-01-01") 
  phaseDT[[i]][, nthIntervention := rowid(session_id)]
}

s + sprintf('
// vars for updating in place
var currLearner = %s
var currEvents:Vector[Event] = Vector.empty[Event]

var currResults: (Array[(Array[Double], Array[Double], Double, Double, Double, Map[Fform, Double], Map[Set[Block], Double], Map[Hyp, Double])], Array[Set[Block]], Dist[Hyp]) = (Array((Array.empty[Double], Array.empty[Double], Double.NaN, Double.NaN, Double.NaN, Map.empty[Fform, Double], Map.empty[Set[Block], Double], Map.empty[Hyp, Double])), Array.empty[Set[Block]], currLearner.hypsDist)
', getModelInitStr("prior1"))

allSess <- unique(phaseDT[[1]]$session_id)

pb <- progress_bar$new(
  format = "  caching [:bar] :percent eta: :eta",
  total = length(allSess), clear = FALSE, width= 60)

for (sess in allSess) {
  pb$tick()
  
  # initialize for phase 1
  s * sprintf('currLearner = %s', getModelInitStr("prior1"))
  
  for (phase in c(1, 2)) {
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
    
    # join and check number of rows (num phase interventions x num possible intervention):
    stopifnot(nrow(fEIGMat) == nrow(sEIGMat))
    joinedMat <- sEIGMat[fEIGMat]
    stopifnot(nrow(joinedMat) == nrow(fEIGMat))
    
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

