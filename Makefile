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

