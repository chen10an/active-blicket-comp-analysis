# Reshape ending chunks into a dataframe containing quiz data indexed by (condition, quiz level, session ID)

##
import pandas as pd
import numpy as np
import pickle
import jmespath
import json
import hashlib

import helperfuns

OUTPUT_DIR_PATH ='../ignore/output/v2/'
RATING_SAVE_PATH = '../ignore/output/v2/quiz_rating.csv'
TEACHING_SAVE_PATH = '../ignore/output/v2/quiz_teaching.csv'

# TODO: exclude/filter inattentive sessions according to prereg
# F_SAVE_PATH = '../ignore/output/nine_combo_quiz_design_matrix.csv'
# with open('../ignore/output/filtered_sessions.pickle', 'rb') as f:
#     filtered_sessions = pickle.load(f)

##
# good ending chunks
with open(os.path.join(OUTPUT_DIR_PATH, 'good_endings.json')) as f:
    ending_chunks = json.load(f)

# query chunks json for quiz-related data
quiz = jmespath.search("[?seq_key=='End'].{sessionId: sessionId, end_time: timestamp, route: route, condition_name: condition_name, score: score, max_score: max_score, is_trouble: is_trouble, quiz_data: quiz_data, l1_final_toggle: task_data.level_1.confidence_toggles[-1].is_confident, l2_final_toggle: task_data.level_2.confidence_toggles[-1].is_confident}", ending_chunks)

##
# this cell is for TESTING/DEVELOPMENT

# develop on a single example before putting into loop:
# l_num = 1
# level_dict = quiz[0]['quiz_data'][f'level_{l_num}']

# rating_data = np.array([level_dict['blicket_rating_groups'], level_dict['correct_blicket_ratings'], level_dict['blicket_rating_scores']]).T
# if l_num == 1:
#     block_ids = np.array([[i for i in range(3)]]).T
# elif l_num == 2:
#     block_ids = np.array([[i+3 for i in range(6)]]).T

# rating_data = np.append(rating_data, block_ids, axis = 1)

# # create all the corresponding column and row/index names
# rating_columns = ['rating', 'true_rating', 'rating_score', 'block']

# pd.DataFrame(data=rating_data, columns=rating_columns)

##
# map a teaching example's detector state to a string representation
state_to_str = {True: '+', False: '-'}

##
rating_sub_df_list = []
teaching_sub_df_list = []
for session in quiz:            
    for l_num in [1,2]:        
        level_dict = session['quiz_data'][f'level_{l_num}']

        # collapse each teaching example into one string
        teaching_ex = [ex['blicket_nonblicket_combo'] + ' ' + state_to_str[ex['detector_state']] for ex in level_dict['teaching_ex']]

        # all teaching-related data for one row
        teaching_data = [teaching_ex + [level_dict['free_response_0'],  level_dict['free_response_1']] + [session[f'l{l_num}_final_toggle']]]

        # all rating-relate data for multiple rows and columns
        rating_data = np.array([level_dict['blicket_rating_groups'], level_dict['correct_blicket_ratings'], level_dict['blicket_rating_scores']]).T
        if l_num == 1:
            block_ids = np.array([[i for i in range(3)]]).T
        elif l_num == 2:
            block_ids = np.array([[i+3 for i in range(6)]]).T
        rating_data = np.append(rating_data, block_ids, axis = 1)

        # create all the corresponding column names
        rating_columns = ['rating', 'true_rating', 'rating_score', 'block']
        teaching_columns = [f'ex_{i}' for i in range(5)] + ['machine_response', 'strategy_response', 'final_toggle_state']

        # combine data and column names into a df row
        rating_sub_df = pd.DataFrame(data=rating_data, columns=rating_columns)
        teaching_sub_df = pd.DataFrame(data=teaching_data, columns=teaching_columns)

        # make (experiment condition, quiz level, session ID) index
        rating_sub_df['condition'] = session['condition_name']
        teaching_sub_df['condition'] = session['condition_name']
        rating_sub_df['level'] = l_num
        teaching_sub_df['level'] = l_num
        rating_sub_df['session_id'] = session['sessionId']
        teaching_sub_df['session_id'] = session['sessionId']

        rating_sub_df.set_index(['condition', 'level', 'session_id', 'block'], inplace=True)
        teaching_sub_df.set_index(['condition', 'level', 'session_id'], inplace=True)

        rating_sub_df_list.append(rating_sub_df)
        teaching_sub_df_list.append(teaching_sub_df)

rating_df = pd.concat(rating_sub_df_list)
teaching_df = pd.concat(teaching_sub_df_list)

# there should only be quiz levels 1,2
# assert set(quiz_df.index.get_level_values('level').unique()) == set([1, 2])
# print("Passed: we have exactly quiz levels 1, 2.")
# print(f"Unique experiment conditions: {list(quiz_df.index.get_level_values('condition').unique())}")
# print(f"Num unique sessions: {len(quiz_df.index.get_level_values('session_id').unique())}")
# print("-----\n")

##
# level 1 blickets are different depending on the condition
rating_df.loc[pd.IndexSlice[['d1_c2', 'nd1_c2'], 1, :, 0], 'is_blicket'] = 1
rating_df.loc[pd.IndexSlice[['d1_c2', 'nd1_c2'], 1, :, [1,2]], 'is_blicket'] = 0

rating_df.loc[pd.IndexSlice[['c1_c2', 'nc1_c2'], 1, :, [0, 1]], 'is_blicket'] = 1
rating_df.loc[pd.IndexSlice[['c1_c2', 'nc1_c2'], 1, :, 2], 'is_blicket'] = 0

rating_df.loc[pd.IndexSlice[['cc1_c2', 'ncc1_c2'], 1, :, [0, 1, 2]], 'is_blicket'] = 1

# level 2 blickets are the same across all conditions
rating_df.loc[pd.IndexSlice[:, 2, :, [3, 4, 5]], 'is_blicket'] = 1
rating_df.loc[pd.IndexSlice[:, 2, :, [6, 7, 8]], 'is_blicket'] = 0

##
# simplify the condition down to just the training form (since this is the only variable manipulated across conditions)
for df in [rating_df, teaching_df]:
    df.reset_index(inplace=True)
    df['training'] = df.condition.apply(lambda x: x.split('_')[0])

##
# make a hash to uniquely identify each row of teaching_df without revealing teaching/level/session_id; to be used later for coding

def hash_row(row):
   legible_id = row.training + str(row.level) + row.session_id  # concatenate all the information needed to identify a row

   # encode and hash to uniquely identify a row without revealing the information above
   encoding = legible_id.encode()
   return hashlib.sha256(encoding).hexdigest()
# test
# dummy_row = pd.DataFrame([['d1', 1, 'longsessionid123']], columns=["training", "level", "session_id"]).iloc[0]
# hash_row(dummy_row)

# make hash id for all rows
teaching_df['hash_id'] = teaching_df.apply(hash_row, axis=1)

##
# split rating vs teaching and filter to columns needed for further analysis/plotting
rating_df = rating_df[['training', 'level', 'session_id', 'block', 'is_blicket', 'rating']]
teaching_df = teaching_df[['training', 'level', 'session_id'] + [f'ex_{i}' for i in range(5)] + ['final_toggle_state', 'machine_response', 'strategy_response', 'hash_id']]

##
rating_df.to_csv(RATING_SAVE_PATH, index = False)
print(f"Saved the v2 quiz rating df to {RATING_SAVE_PATH}!")

##
teaching_df.to_csv(TEACHING_SAVE_PATH, index = False)
print(f"Saved the v2 quiz teaching df to {TEACHING_SAVE_PATH}!")

##
# f_design_df.to_csv(F_SAVE_PATH)
# print(f"Saved the filtered design matrix to {F_SAVE_PATH}!")
