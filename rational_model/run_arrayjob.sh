# make sure repos and the scala model jar are up to date
cd ~/projects/active-overhypo-learner/ && git pull && sbt package 
cd ~/projects/active-blicket-comp-analysis/rational_model && git pull

EXPT_FILE=2022-03-22_mix_experiments.txt  # <- this has a command to run on each line
NR_EXPTS=`cat ${EXPT_FILE} | wc -l`
MAX_PARALLEL_JOBS=12 

sbatch --array=1-${NR_EXPTS}%${MAX_PARALLEL_JOBS} arrayjob.sh $EXPT_FILE
