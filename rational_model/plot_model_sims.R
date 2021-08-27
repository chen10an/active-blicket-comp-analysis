library(data.table)
library(magrittr)
library(rscala)
source("../plots_and_stats/plotting_helperfuns.R")
s <- scala(JARs = "~/projects/active-overhypo-learner/target/scala-2.13/active-overhypothesis-learner_2.13-0.0.0.jar")
s + '
import utils._
import learner._
'
grid <- fread("cache/bias-shape=5-scale=0.1_gain-shape=100-scale=0.1_grid.csv")

# MODELNAME <- "sigPrag-5-0.1-100-0.1"
MODELNAME <- "enum-uniform"
# PRIORSTR <- 'PriorMaker.makeSigmoidPrior(bgToP, blocksMap(phaseNum), true)'
PRIORSTR <- 'PriorMaker.makeEnumeratedPrior(fformToP, blocksMap(phaseNum), false)'
LEARNERSTR <- "new PhaseLearner(makePrior(phaseNum))"
PHASES <- c("d1", "nd1", "c1", "nc1", "cc1", "ncc1")
NSIMS <- 20
NINTERVENTIONS <- 12

# check all phases are formatted correctly
stopifnot(all(grepl("[ncd]+[123]{1}", PHASES)))

s + '
val blocksMap = Map[Int, Set[Block]](
 1 -> Set("0", "1", "2").map(Block(_)),
 2 -> Set("0", "1", "2", "3", "4", "5").map(Block(_)),
 3 -> Set("0", "1", "2", "3", "4", "5", "6", "7", "8").map(Block(_))
)

val fformToP = Set(PriorMaker.disj, PriorMaker.conj, PriorMaker.conj3, PriorMaker.noisy_disj, PriorMaker.noisy_conj, PriorMaker.noisy_conj3).map(form => (form, 1.0/6)).toMap
'

# only relevant if using the gain-bias grid for initializing Learner: create a lookup table for the joint gamma densities of biases and gains
s + 'var bgToP = Map.empty[(Double, Double),Double]'
s(grid = as.matrix(grid)) * '
bgToP = grid.map(arr => (arr(0), arr(1)) -> arr(2)).toMap
'

s + sprintf('
def makePrior(phaseNum: Int) = {
  %s
}
', PRIORSTR)

s + sprintf('
def makeLearner(phaseNum: Int) = {
  %s
}
', LEARNERSTR)

s + '
val d1sim = Simulator(Set("0").map(Block(_)), PriorMaker.disj)
val c1sim = Simulator(Set("0", "1").map(Block(_)), PriorMaker.conj)
val nd1sim = Simulator(Set("0").map(Block(_)), PriorMaker.noisy_disj)
val nc1sim = Simulator(Set("0", "1").map(Block(_)), PriorMaker.noisy_conj)

val cc1sim = Simulator(Set("0", "1", "2").map(Block(_)), PriorMaker.conj3)
val ncc1sim = Simulator(Set("0", "1", "2").map(Block(_)), PriorMaker.noisy_conj3)

val d2sim = Simulator(Set("0", "1", "2").map(Block(_)), PriorMaker.disj)
val c2sim = Simulator(Set("0", "1", "2").map(Block(_)), PriorMaker.conj)

// val d3sim = Simulator(Set("0", "1", "2", "3").map(Block(_)), PriorMaker.disj)
// val c3sim = Simulator(Set("0", "1", "2", "3").map(Block(_)), PriorMaker.conj)

var simResults = Array.empty[Array[(Event, Double, Map[Hyp, Double], Map[Fform, Double], Map[Set[Block], Double])]]
var allBlocks = Set.empty[Block]
'

for (phase in PHASES) {
  simstring <- sprintf('
simResults = %ssim.run(makeLearner(%s), %i, %i)
allBlocks = blocksMap(%s)
', phase, sub(".*([0-9])", "\\1", phase), NSIMS, NINTERVENTIONS, sub(".*([0-9])", "\\1", phase))
  
  print(simstring)
  
  s + simstring
  
  comboMat <- s * '
// intervention matrix
simResults.map(_.map(_._1.blocks.map(_.name).mkString(",")))
'
  comboDT <- data.table(comboMat)
  
  outcomeMat <- s * '
// corresponding outcome (T/F) matrix
simResults.map(_.map(_._1.outcome))
'
  
  # vector of convergence index, indexed by simulation number
  convergeDexVec <- s * '
// for every intervention y (within simulation x), test if the highest probability density hypotheses are the same with the last intervention
val alreadyConverged = simResults.map(x => x.map(y => y._3.keys == x.last._3.keys))

// for every simulation, convergence happened one intervention after the first false from the right; add another 1 to shift the indexing to match with R (starting from 1, not 0)
alreadyConverged.map(_.lastIndexOf(false) + 1 + 1)
  '
  
  simDT <- data.table(simID = numeric(),
                      nthIntervention = numeric(),
                      outcome = logical(),
                      hasConverged= logical())
  allIdCols <- s * 'allBlocks.map("id_" + _.name).toArray'
  allIdCols <- sort(allIdCols)
  
  dtList <- list()
  counter <- 1
  for (simN in 1:nrow(comboMat)) {
    for (comboN in 1:ncol(comboMat)) {
      combo <- comboMat[simN, comboN]
      outcome <- outcomeMat[simN, comboN]
      hasConverged <- comboN >= convergeDexVec[simN]
      
      onIdCols <- strsplit(combo, ",") %>% unlist()
      if (length(onIdCols) > 0 & onIdCols[1] == "STOP") {
        break
      }
      
      rowDT <- data.table(simID = simN,  # simN will always uniquely match to this row of data, even when this script is rerun, because a random seed has been set in the scala code
                          nthIntervention = comboN,
                          outcome = outcome,
                          hasConverged = hasConverged)
      rowDT[, (allIdCols) := 0]
      
      if (length(onIdCols) > 0) {
        # if the intervention chose a non-empty combination of blocks
        onIdCols <- paste0("id_", onIdCols)
        rowDT[, (onIdCols) := 1] 
      }
      
      dtList[[counter]] <- rowDT
      counter <- counter + 1
    }
  }
  
  simDT <- rbindlist(dtList)
  simDT
  
  pbi <- 1
  pbmax <- length(unique(simDT$simID))
  pb <- txtProgressBar(min = 0, max = pbmax, style = 3)
  # save one plot per sim
  for (id in unique(simDT$simID)) {
    sessDT <- simDT[simID == id]
    
    # melt (wide to long) for plotting
    sessDT <- melt(sessDT, measure.vars = allIdCols, variable.name = "block_id", value.name = "block_state")
    
    p <- ggplot(data = sessDT, aes(x = nthIntervention, y = block_state, fill = outcome)) +
      geom_col(width = 0.1) +
      scale_fill_brewer(palette = "Dark2", direction = -1) +
      facet_grid("block_id ~ .") +
      geom_vline(xintercept = which(sessDT$hasConverged)[1], linetype="dotted") +  # put a vertical line at the first intervention where the highest probability density hypotheses has already converged (i.e., match with the last intervention)
      theme_pubr() +
      theme(panel.spacing = unit(0, "lines"),
            axis.text.y=element_blank(),
            axis.ticks.y=element_blank())
    
    # TODO: indicate space/prior, phase and form
    
    # create the save path if it doesn't exist and then save
    saveDir <- sprintf("plots/sims/%s/%s", MODELNAME, phase)
    saveFile <- sprintf("%s_%s.png", phase, id)
    if (!dir.exists(saveDir)) {
      dir.create(saveDir, recursive = TRUE)
    }
    save_plot(file.path(saveDir, saveFile), plot = p, base_width = 3, base_height = 2)
    
    setTxtProgressBar(pb, pbi)
    pbi <- pbi + 1
  }
  close(pb)
  
}
