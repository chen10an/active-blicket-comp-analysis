v2:
	# only run analyses specific to v2xx of the active-blicket-comp experiment
	cd preprocessing_scripts && \
	python v2_save_good_endings.py && \
	python v2_preprocess_quiz.py && \
	python v2_preprocess_interventions.py

micro:
	cd preprocessing_scripts && \
	python v2_save_good_endings.py && \
	python v2_preprocess_micro.py

