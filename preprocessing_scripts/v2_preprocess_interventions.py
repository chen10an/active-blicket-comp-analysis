# Reshape ending chunks into a dataframe containing intervention data

##
import pandas as pd
import json
import jmespath
import numpy as np

SKIP_PILOT = True
OUTPUT_DIR_PATH ='../ignore/output/v2/'

# good ending chunks
with open(os.path.join(OUTPUT_DIR_PATH, 'good_endings.json')) as f:
    ending_chunks = json.load(f)

##
# query chunks json for task-related data
l1_task = jmespath.search("[?seq_key=='End'].{sessionId: sessionId, end_time: timestamp, condition_name: condition_name, task_data: task_data.level_1.all_combos}", ending_chunks)

l2_task = jmespath.search("[?seq_key=='End'].{sessionId: sessionId, end_time: timestamp, condition_name: condition_name, task_data: task_data.level_2.all_combos}", ending_chunks)

##
# TODO: incorporate toggle in a way that's backward compatible with how I've set up R/scala code to work with the current intervention format

task_lists = {1: l1_task, 2: l2_task}  # keyed by level
task_dfs = {}  # for storing resulting dfs
for level, task in task_lists.items():
    # start creating rows for the resulting dataframe
    rows = []
    for session in task:
        # skip pilot data via filtering on timestamp that's definitely after the pilot (but before the main exp)
        if SKIP_PILOT and pd.to_datetime(session['end_time'], unit='ms') <= pd.Timestamp('2021-09-05 00:00:00'):
            continue

        condition_name = session['condition_name']

        # prep the index for the resulting dataframe
        partial_index = [condition_name, session['sessionId']]
        
        timestamps = jmespath.search("[*].timestamp", session[f'task_data'])
        combos = jmespath.search("[*].bitstring", session[f'task_data'])
        outcomes = jmespath.search("[*].activates_detector", session[f'task_data'])
        
        for i in range(len(timestamps)):
            full_index = partial_index + [timestamps[i]]
            
            # use numpy to change type to int
            # then change back list so we can have multi-type rows
            current_combo = np.array(list(combos[i])).astype(int)
            current_combo = list(current_combo)

            current_outcome = [outcomes[i]]

            rows.append(full_index + current_combo + current_outcome)

    num_blocks = level*3  # 3 blocks in l1, 6 in l2
    task_df = pd.DataFrame(rows, columns=
                           ['condition', 'session_id', 'timestamp'] +
                           [f'id_{i}' for i in range(num_blocks)] + ['outcome'])

    # don't set as pandas index because I don't really need their functionality here
    # task_df.set_index(['condition', 'session_id', 'timestamp'], inplace=True)
    task_dfs[level] = task_df

##
# fill in exact phase
for level, df in task_dfs.items():
    if level == 1:
        df['phase'] = df.condition.str.split('_', expand=True)[0]
    elif level == 2:
        df['phase'] = df.condition.str.split('_', expand=True)[1]

# check possible values of phases
assert(set(task_dfs[1].phase.unique()).issubset({'d1', 'nd1', 'c1', 'nc1', 'cc1', 'ncc1'}))
assert(task_dfs[2].phase.unique() == ['c2'])

##
# save
save_path_1 = os.path.join(OUTPUT_DIR_PATH, 'interventions1.csv')
task_dfs[1].to_csv(save_path_1)
print(f"Saved phase 1 interventions to {save_path_1}!")

save_path_2 = os.path.join(OUTPUT_DIR_PATH, 'interventions2.csv')
task_dfs[2].to_csv(save_path_2)
print(f"Saved phase 2 interventions to {save_path_2}!")
