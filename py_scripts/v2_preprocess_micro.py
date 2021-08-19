# Preprocess micro experiment data

##
import pandas as pd
import numpy as np
import pickle
import jmespath
import json
import hashlib

import helperfuns

OUTPUT_DIR_PATH ='../ignore/output/v2/'
TEACHING_SAVE_PATH = '../ignore/output/v2/micro_teaching.csv'

##
# good ending chunks
with open(os.path.join(OUTPUT_DIR_PATH, 'good_endings_micro.json')) as f:
    ending_chunks = json.load(f)

# query chunks json for quiz-related data
quiz = jmespath.search("[?seq_key=='End'].{sessionId: sessionId, end_time: timestamp, route: route, condition_name: condition_name, is_trouble: is_trouble, quiz_data: quiz_data}", ending_chunks)

##
# map a teaching example's detector state to a string representation
state_to_str = {True: '+', False: '-'}

##
teaching_sub_df_list = []
for session in quiz:            
    for key in session['quiz_data'].keys():        
        level_dict = session['quiz_data'][key]

        # collapse each teaching example into one string
        teaching_ex = [ex['blicket_nonblicket_combo'] + ' ' + state_to_str[ex['detector_state']] for ex in level_dict['teaching_ex']]

        # all teaching-related data for one row
        teaching_data = [teaching_ex]

        # create all the corresponding column names
        teaching_columns = [f'ex_{i}' for i in range(5)]

        # combine data and column names into a df row
        teaching_sub_df = pd.DataFrame(data=teaching_data, columns=teaching_columns)

        teaching_sub_df['condition'] = session['condition_name']
        teaching_sub_df['true_form'] = key
        teaching_sub_df['session_id'] = session['sessionId']
        # teaching_sub_df.set_index(['true_form', 'session_id'], inplace=True)

        teaching_sub_df_list.append(teaching_sub_df)

teaching_df = pd.concat(teaching_sub_df_list, ignore_index=True)

##
# make a hash to uniquely identify each row of teaching_df without revealing the ground truth information; to be used later for coding

def hash_row(row):
   legible_id = row.true_form + row.session_id  # concatenate all the information needed to identify a row

   # encode and hash to uniquely identify a row without revealing the information above
   encoding = legible_id.encode()
   return hashlib.sha256(encoding).hexdigest()
# test
# dummy_row = pd.DataFrame([['d1', 1, 'longsessionid123']], columns=["training", "level", "session_id"]).iloc[0]
# hash_row(dummy_row)

# make hash id for all rows
teaching_df['hash_id'] = teaching_df.apply(hash_row, axis=1)

##
# filter to columns needed for further analysis/plotting
teaching_df = teaching_df[['condition', 'true_form', 'session_id'] + [f'ex_{i}' for i in range(5)] + ['hash_id']]

##
teaching_df.to_csv(TEACHING_SAVE_PATH, index = False)
print(f"Saved the v2 micro teaching df to {TEACHING_SAVE_PATH}!")
