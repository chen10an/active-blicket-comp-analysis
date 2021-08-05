# Reshape ending chunks into a dataframe containing quiz data indexed by (condition, quiz level, session ID)

##
import pandas as pd
import numpy as np
import pickle
import jmespath
import json

import helperfuns

OUTPUT_DIR_PATH ='../ignore/output/'
RATING_SAVE_PATH = '../ignore/output/v2_quiz_rating.csv'
TEACHING_SAVE_PATH = '../ignore/output/v2_quiz_teaching.csv'

# TODO: exclude/filter inattentive sessions according to prereg
# F_SAVE_PATH = '../ignore/output/nine_combo_quiz_design_matrix.csv'
# with open('../ignore/output/filtered_sessions.pickle', 'rb') as f:
#     filtered_sessions = pickle.load(f)

##
# good ending chunks
with open(os.path.join(OUTPUT_DIR_PATH, 'v2_good_endings.json')) as f:
    ending_chunks = json.load(f)

# query chunks json for quiz-related data
quiz = jmespath.search("[?seq_key=='End'].{sessionId: sessionId, end_time: timestamp, route: route, condition_name: condition_name, score: score, max_score: max_score, is_trouble: is_trouble, quiz_data: quiz_data, l1_final_toggle: task_data.level_1.confidence_toggles[-1].is_confident, l2_final_toggle: task_data.level_2.confidence_toggles[-1].is_confident}", ending_chunks)

##
# this cell is for TESTING/DEVELOPMENT

# # develop on a single example before putting into loop:
# level_dict = quiz[0]['quiz_data'][f'level_1']

# # map a teaching example's detector state to a string representation
# state_to_str = {True: '+', False: '-'}
# # collapse each teaching example into one string
# teaching_ex = [ex['blicket_nonblicket_combo'] + ' ' + state_to_str[ex['detector_state']] for ex in level_dict['teaching_ex']]

##
# map a teaching example's detector state to a string representation
state_to_str = {True: '+', False: '-'}

##
blicket_rows = []
for session in quiz:            
    for l_num in [1,2]:        
        level_dict = session['quiz_data'][f'level_{l_num}']

        # collapse each teaching example into one string
        teaching_ex = [ex['blicket_nonblicket_combo'] + ' ' + state_to_str[ex['detector_state']] for ex in level_dict['teaching_ex']]

        
        # create all the data for one row
        level_data = level_dict['blicket_rating_groups'] + level_dict['correct_blicket_ratings'] + level_dict['blicket_rating_scores'] + teaching_ex + [level_dict['free_response_0'],  level_dict['free_response_1']] + [session[f'l{l_num}_final_toggle']]

        # create all the corresponding column names
        if l_num == 1:
            columns = [f'rating_{i}' for i in range(3)] + [f'true_rating_{i}' for i in range(3)] + [f'rating_score_{i}' for i in range(3)]
        elif l_num == 2:
            columns = [f'rating_{i+3}' for i in range(6)] + [f'true_rating_{i+3}' for i in range(6)] + [f'rating_score_{i+3}' for i in range(6)]

        columns += [f'ex_{i}' for i in range(5)]
        columns += ['machine_response', 'strategy_response', 'final_toggle_state']

        # combine data and column names into a df row
        level_row = pd.DataFrame(data=[level_data], columns=columns)
        # the brackets around level_data are needed to recognize it as a row, not column

        # make (experiment condition, quiz level, session ID) index
        level_row['condition'] = session['condition_name']
        level_row['level'] = l_num
        level_row['session_id'] = session['sessionId']

        level_row.set_index(['condition', 'level', 'session_id'], inplace=True)
        blicket_rows.append(level_row)

quiz_df = pd.concat(blicket_rows)

# there should only be quiz levels 1,2
assert set(quiz_df.index.get_level_values('level').unique()) == set([1, 2])
print("Passed: we have exactly quiz levels 1, 2.")
print(f"Unique experiment conditions: {list(quiz_df.index.get_level_values('condition').unique())}")
print(f"Num unique sessions: {len(quiz_df.index.get_level_values('session_id').unique())}")
print("-----\n")

##
# level 1 blickets are different depending on the condition
quiz_df.loc[pd.IndexSlice[['d1_c2', 'nd1_c2'], 1, :], 'blicket_mean_rating'] = quiz_df.loc[pd.IndexSlice[['d1_c2', 'nd1_c2'], 1, :], 'rating_0']
quiz_df.loc[pd.IndexSlice[['d1_c2', 'nd1_c2'], 1, :], 'nonblicket_mean_rating'] = quiz_df.loc[pd.IndexSlice[['d1_c2', 'nd1_c2'], 1, :], ['rating_1', 'rating_2']].mean(axis=1)

quiz_df.loc[pd.IndexSlice[['c1_c2', 'nc1_c2'], 1, :], 'blicket_mean_rating'] = quiz_df.loc[pd.IndexSlice[['c1_c2', 'nc1_c2'], 1, :], ['rating_0', 'rating_1']].mean(axis=1)
quiz_df.loc[pd.IndexSlice[['c1_c2', 'nc1_c2'], 1, :], 'nonblicket_mean_rating'] = quiz_df.loc[pd.IndexSlice[['c1_c2', 'nc1_c2'], 1, :], 'rating_2']

quiz_df.loc[pd.IndexSlice[['cc1_c2', 'ncc1_c2'], 1, :], 'blicket_mean_rating'] = quiz_df.loc[pd.IndexSlice[['cc1_c2', 'ncc1_c2'], 1, :], ['rating_0', 'rating_1', 'rating_2']].mean(axis=1)
quiz_df.loc[pd.IndexSlice[['cc1_c2', 'ncc1_c2'], 1, :], 'nonblicket_mean_rating'] = None  # no nonblickets

# level 2 blickets are the same across all conditions
quiz_df.loc[pd.IndexSlice[:, 2, :], 'blicket_mean_rating'] = quiz_df.loc[pd.IndexSlice[:, 2, :], ['rating_3', 'rating_4', 'rating_5']].mean(axis=1)
quiz_df.loc[pd.IndexSlice[:, 2, :], 'nonblicket_mean_rating'] = quiz_df.loc[pd.IndexSlice[:, 2, :], ['rating_6', 'rating_7', 'rating_8']].mean(axis=1)

# sanity check:
# quiz_df[['blicket_mean_rating', 'nonblicket_mean_rating'] + [f'rating_{i}' for i in range(9)]].to_csv('~/Downloads/temp.csv')

##
# simplify the condition down to just the training form (since this is the only variable manipulated across conditions)
quiz_df.reset_index(inplace=True)
quiz_df['training'] = quiz_df.condition.apply(lambda x: x.split('_')[0])

##
# split rating vs teaching and filter to columns needed for further analysis/plotting
rating_df = quiz_df[['training', 'level', 'session_id', 'blicket_mean_rating', 'nonblicket_mean_rating']]
teaching_df = quiz_df[['training', 'level', 'session_id'] + [f'ex_{i}' for i in range(5)] + ['final_toggle_state', 'machine_response', 'strategy_response']]

##
rating_df.to_csv(RATING_SAVE_PATH)
print(f"Saved the v2 quiz rating df to {RATING_SAVE_PATH}!")

##
teaching_df.to_csv(TEACHING_SAVE_PATH)
print(f"Saved the v2 quiz teaching df to {TEACHING_SAVE_PATH}!")

##
# f_design_df.to_csv(F_SAVE_PATH)
# print(f"Saved the filtered design matrix to {F_SAVE_PATH}!")
