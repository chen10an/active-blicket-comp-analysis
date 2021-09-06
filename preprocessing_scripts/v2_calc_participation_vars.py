##
import pandas as pd
import numpy as np
import json
import pickle
import os
import jmespath

DATA_DIR_PATH = '../ignore/data/'
OUTPUT_DIR_PATH = '../ignore/output/v2/'

with open(os.path.join(DATA_DIR_PATH, 'chunks_200-mturk.json')) as f:
    all_chunks = json.load(f)

# good ending chunks
with open(os.path.join(OUTPUT_DIR_PATH, 'good_endings.json')) as f:
    ending_chunks = json.load(f)

##
# query chunks json for start and end times

start_df = pd.DataFrame(jmespath.search("[?seq_key=='IntroInstructions'].{sessionId: sessionId, start_time: timestamp, route: route, condition_name: condition_name, is_trouble: is_trouble}", all_chunks)).set_index('sessionId')

end_df = pd.DataFrame(jmespath.search("[?seq_key=='End'].{sessionId: sessionId, end_time: timestamp, route: route, condition_name: condition_name, is_trouble: is_trouble}", ending_chunks)).set_index('sessionId')

# convert to datetime
start_df.loc[:, 'start_time'] = pd.to_datetime(start_df.start_time, unit='ms')
end_df.loc[:, 'end_time'] = pd.to_datetime(end_df.end_time, unit='ms')

##
# filter to start df to sessions that correspond good endings
start_df = start_df.loc[start_df.index.get_level_values('sessionId').isin(end_df.index.get_level_values('sessionId'))]

assert start_df.shape[0] == end_df.shape[0]

##
# index on index inner join
joined_df = start_df.join(end_df, how='inner', lsuffix='_end', rsuffix='_start')

##
# series of time differences
diff = joined_df.end_time - joined_df.start_time

# mean completion time (end-start) excluding time for reading instructions
mean_completion_min = diff.mean() / pd.Timedelta('1min')
mean_completion_min = np.round(mean_completion_min, 2)  # 2 decimal places

##
# create dict to be saved
my_vars = {}
my_vars['completionTime'] = f'{mean_completion_min} minutes'
