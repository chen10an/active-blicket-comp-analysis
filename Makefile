v2:
	# only run analyses specific to v2xx of the active-blicket-comp experiment
	cd preprocessing_scripts
	python v2_save_good_endings.py
	python v2_save_quiz_design_matrix.py

micro:
	cd preprocessing_scripts && \
	python v2_save_good_endings.py && \
	python v2_preprocess_micro.py

