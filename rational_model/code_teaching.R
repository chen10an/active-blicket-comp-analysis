# This script calls the rational model to "code" participants' teaching examples by conditioning on their examples as if they were passive evidence. The model's "coding" is a distribution over the 6 possible forms [disj, noisy_disj, conj, noisy_conj, conj3, noisy_conj3].

library(data.table)
library(magrittr)
library(rscala)
library(progress)
source("helperfuns.R")
s <- scala(JARs = "~/projects/active-overhypo-learner/target/scala-2.13/active-overhypothesis-learner_2.13-0.0.0.jar")
s + '
import utils._
import learner._
'

microDT <- fread(file="../ignore/output/v2/marked_teaching_micro.csv")
mainDT <- fread(file="../ignore/output/v2/marked_teaching.csv")  # does not include pilot

# dedup dt (since there are 2 copies of participant data, 1 per coder)
microDT <- unique(microDT , by=c("hash_id"))
mainDT <- unique(mainDT , by=c("hash_id"))
stopifnot(nrow(microDT) == 26*7)  # 26 participants, 7 example sets
stopifnot(nrow(mainDT) == 250*2)  # 250 participants, 2 example sets

# prior and model choice:
s + '
val blocksMap = Map[Int, Set[Block]](
  // for modeling when the structure is known, i.e., the blickets (*) are known; can be used for all tasks with up to 9 blickets
  -1 -> Set("*0", "*1", "*2", "*3", "*4", "*5", "*6", "*7", "*8").map(Block(_))
)

// disj and noisy_disj favoring enumerated prior
val fformToP = Set(PriorMaker.disj, PriorMaker.conj, PriorMaker.conj3, PriorMaker.noisy_disj, PriorMaker.noisy_conj, PriorMaker.noisy_conj3).map(form => if (form == PriorMaker.disj || form == PriorMaker.noisy_disj) (form, 0.45) else (form, 0.1/4)).toMap

// only one known structure
val knownStructEnumPrior: Dist[Hyp] = Dist(fformToP.map{case (fform, p) => {Hyp(blocksMap(-1), fform) -> p}})
assert(knownStructEnumPrior.atoms.values.sum == 1.0)
'

s + '
// vars for updating in place
var currLearner = new PhaseLearner(knownStructEnumPrior)
var currEvents:Vector[Event] = Vector.empty[Event]
var currResults: Map[Fform, Double] = Map.empty[Fform, Double]
var currOrderedResKeys: Array[Fform] = Array.empty[Fform]  // use same order to retrieve both the key (fform) and value (probability)

// handle R vector with one element (scala string) vs multiple elements (scala array)
def ensureArr(v: Any): Array[String] = v match {
  case v: Array[String] => v
  case v: String => Array(v)
}
'

for (expType in c("micro", "main")) {
  if (expType == "micro") {
    expDT <- microDT
  } else if (expType == "main") {
    expDT <- mainDT
  } else {
    stop()
  }

  # each hash identifies a single example set
  allHash <- unique(expDT$hash_id)
  
  exCols <- sapply(0:4, function(i) sprintf("ex_%i", i))
  
  pb <- progress_bar$new(
    format = "  caching [:bar] :percent eta: :eta",
    total = length(allHash), clear = FALSE, width= 60)
  
  resList <- list()
  for (hash in allHash) {
    pb$tick()
    dt <- expDT[hash_id == hash]
    
    # re-initialize
    s * 'currLearner = new PhaseLearner(knownStructEnumPrior)'
    s * 'currEvents = Vector.empty[Event]'
    
    for (col in exCols) {
      ex <- dt[[col]]
      stopifnot(typeof(ex) == "character" && length(ex) == 1)  # single string
      
      rblocks <- substr(ex, 1, nchar(ex)-2)  # blickets (*) and non-blickets (.)
      rblocks <- strsplit(rblocks, "") %>% unlist()  # vector of individual blocks
      stopifnot(all(sapply(rblocks, function(b) b %in% c("*", "."))))
      
      # represent blicket ids as "<0-indexed position>*" and non-blickets as "<0-indexed position>.", e.g., a combination could look like "0*, 1., 2*", where the number always corresponds to the position and only the */. label changes
      rblocks <- sapply(1:length(rblocks), function(i) paste0(rblocks[i],i-1))
      
      routcome <- substr(ex, nchar(ex), nchar(ex))  # "+" or "-"
      if (routcome == "+") {
        routcome <- TRUE
      } else if (routcome == "-") {
        routcome <- FALSE
      }
      stopifnot(routcome %in% c(TRUE, FALSE))
      
      s (rblocks, routcome) * '
      val blocks = ensureArr(rblocks)
      val outcome = routcome
      val intervention: Set[Block] = blocks.map(b => Block(b)).toSet
      
      currEvents = currEvents :+ Event(intervention, outcome)
      '
    }
    
    s * '
    currResults = currLearner.update(currEvents).hypsDist.fformMarginalAtoms
    currOrderedResKeys = currResults.keys.toArray  // retrieve both keys and values in this order
    '
    
    possForms <- s * 'currOrderedResKeys.map(_.name)'
    modelP <- s * 'currOrderedResKeys.map(currResults(_))'  # model's "coding"
    
    # add a possible form for "other" if the model assign 0 probability to all of the forms in its hypothesis space
    possForms <- c(possForms, "other")
    otherP <- as.numeric(all(modelP == 0))
    modelP <- c(modelP, otherP)
    
    # to be concatenated later with the other hash ids
    resDT <- data.table(
      hash_id=hash,  # recycle single value
      possForms, 
      modelP)
    
    resList[[hash]] = resDT
  }
  
  allResDT <- rbindlist(resList)
  setkey(allResDT, hash_id)
  setkey(expDT, hash_id)
  
  joinedDT <- expDT[allResDT, nomatch = 0]  # inner
  stopifnot(nrow(joinedDT) == nrow(allResDT))
  
  saveDT(joinedDT, "coding_teaching", sprintf("coded_teaching_%s.csv",expType))
}
