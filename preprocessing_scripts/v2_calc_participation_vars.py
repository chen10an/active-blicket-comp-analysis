##
import pandas as pd
import numpy as np
import json
import pickle
import os
import jmespath
import re

DATA_DIR_PATH = '../ignore/data/'
OUTPUT_DIR_PATH = '../ignore/output/v2/'
SAVE_PATH = os.path.join(OUTPUT_DIR_PATH, 'my_vars.json')

SKIP_PILOT = True

with open(os.path.join(DATA_DIR_PATH, 'chunks_200-mturk.json')) as f:
    all_chunks = json.load(f)

# good ending chunks
with open(os.path.join(OUTPUT_DIR_PATH, 'good_endings.json')) as f:
    ending_chunks = json.load(f)

# create dict to be saved
my_vars = {}

##
# query chunks json for start and end times

start_df = pd.DataFrame(jmespath.search("[?seq_key=='IntroInstructions'].{sessionId: sessionId, start_time: timestamp, route: route, condition_name: condition_name, is_trouble: is_trouble}", all_chunks)).set_index('sessionId')

end_df = pd.DataFrame(jmespath.search("[?seq_key=='End'].{sessionId: sessionId, end_time: timestamp, route: route, condition_name: condition_name, is_trouble: is_trouble, total_bonus: total_bonus}", ending_chunks)).set_index('sessionId')

# convert to datetime
start_df.loc[:, 'start_time'] = pd.to_datetime(start_df.start_time, unit='ms')
end_df.loc[:, 'end_time'] = pd.to_datetime(end_df.end_time, unit='ms')

##
# skip pilot data via filtering on timestamp that's definitely after the pilot (but before the main exp)
if SKIP_PILOT:
    end_df = end_df[end_df['end_time'] >= pd.Timestamp('2021-09-05 00:00:00')]
    
##
# filter to start df to sessions that correspond good endings
start_df = start_df.loc[start_df.index.get_level_values('sessionId').isin(end_df.index.get_level_values('sessionId'))]

assert start_df.shape[0] == end_df.shape[0]

##
# index on index inner join
joined_df = start_df.join(end_df, how='inner', lsuffix='_end', rsuffix='_start')

##
# all participants
my_vars['totalN'] = joined_df.reset_index().sessionId.nunique()

# per condition participants
cond_df = end_df.reset_index().groupby('condition_name').sessionId.nunique()
for index, val in cond_df.items():
    clean_command = re.sub('\d', '', index).replace('_', '') + 'N'  # remove all underscores and numbers to create a valid latex command
    my_vars[clean_command] = val

##
# series of time differences
diff = joined_df.end_time - joined_df.start_time

# mean completion time (end-start) excluding time for reading instructions
mean_completion_min = diff.mean() / pd.Timedelta('1min')
mean_completion_min = np.round(mean_completion_min, 2)  # 2 decimal places

my_vars['completionTime'] = f'{mean_completion_min} minutes'

##

# this is for blicket questions only:
mean_bonus = end_df.total_bonus.mean()
mean_total_comp = mean_bonus + 1.28
my_vars['blicketTotalComp'] = f'{mean_total_comp:.2f}'  # 2 decimal places
my_vars['hourlyBlicketTotalComp'] = f'{(mean_total_comp/mean_completion_min*60):.2f}'  # 2 decimal places

##
with open(SAVE_PATH, 'w') as f:
    json.dump(my_vars, f, indent=4)
    
print(f"Saved participation variables in {SAVE_PATH}!")
