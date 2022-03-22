v2:
	# only run analyses specific to v2xx of the active-blicket-comp experiment
	cd preprocessing_scripts && \
	python v2_save_good_endings.py && \
	python v2_preprocess_quiz.py && \
	python v2_preprocess_interventions.py

v2-vars:
	cd preprocessing_scripts && \
	python v2_calc_participation_vars.py && \
	python v2_make_latex_vars.py

micro:
	cd preprocessing_scripts && \
	python v2_save_good_endings.py && \
	python v2_preprocess_micro.py

v2-send:
	# send preprocessed intervention data to cluster for running model conditioning on those interventions
	ssh s2064559@ilcc-cluster.inf.ed.ac.uk "mkdir -p ~/projects/active-blicket-comp-analysis/ignore/output/v2/"  # make directories
	scp ignore/output/v2/interventions1.csv s2064559@ilcc-cluster.inf.ed.ac.uk:~/projects/active-blicket-comp-analysis/ignore/output/v2/interventions1.csv
	scp ignore/output/v2/interventions2.csv s2064559@ilcc-cluster.inf.ed.ac.uk:~/projects/active-blicket-comp-analysis/ignore/output/v2/interventions2.csv
