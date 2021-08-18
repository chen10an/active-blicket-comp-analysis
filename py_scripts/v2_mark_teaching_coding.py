# Mark whether participants' teaching examples (with coded forms) are matched to the ground truth forms

##
import pandas as pd
import numpy as np
import os

BONUS = 0.16  # possible bonus per set/level of teaching questions
OUTPUT_DIR_PATH = '../ignore/output/v2/'
CODING_DIR_PATH = '../ignore/output/v2/coding/'

SAVE_PATH = '../ignore/output/v2/coding/bonus_teaching_coding_20x-mturk_pilot.csv'

# load coded teaching examples
coded_df = pd.read_csv(os.path.join(CODING_DIR_PATH, 'done_teaching_coding_20x-mturk_pilot.csv'))

# load teaching examples with their associated ground truth information (i.e., session_id, training/form, level)
truth_df = pd.read_csv(os.path.join(OUTPUT_DIR_PATH, 'quiz_teaching.csv'))

##
# label every row with a shorthand name for the ground truth form

# for level 1, the shorthand name is just the same as training without the level '1' part
truth_df.loc[truth_df.level == 1, 'true_short_form'] = truth_df.loc[truth_df.level == 1].training.apply(lambda x: x.replace('1', ''))

# the level 2 form is always 'c' (deterministic conjunctive)
truth_df.loc[truth_df.level == 2, 'true_short_form'] = 'c'

##
# join on hash id, getting rid of the randomly generated rows
merged_df = truth_df.merge(coded_df, on='hash_id', how='left')

##
# match coding to corresponding shorthand name for the ground truth form
# format is (form, is_noisy): shorthand form
code_to_shorthand_form = {
    ('disj', False): 'd',
    ('disj', True): 'nd',
    ('conj', False): 'c',
    ('conj', True): 'nc',
    ('conj3', False): 'cc',
    ('conj3', True): 'ncc'
    }

def convert_to_shorthand_form(row):
    if pd.isnull(row.form):
        # if the coded form is nan, just return nan again
        return np.nan
    
    return code_to_shorthand_form[(row.form, row.is_noisy)]

merged_df['coded_short_form'] = merged_df.apply(convert_to_shorthand_form, axis=1)

##
merged_df['is_correct'] = False
merged_df.loc[merged_df.coded_short_form == merged_df.true_short_form, 'is_correct'] = True

# column needed for mturk bonusing
merged_df['BonusAmount'] = 0.0
merged_df.loc[merged_df.is_correct, 'BonusAmount'] = BONUS

# view
merged_df[['training', 'true_short_form', 'coded_short_form', 'is_correct', 'BonusAmount']]

##
# filter out columns not needed for mturk bonusing
bonus_df = merged_df[['session_id', 'BonusAmount']]

# add up bonus per session/participant
bonus_df = bonus_df.groupby('session_id').sum()

##
# save
bonus_df.to_csv(SAVE_PATH)
print(f"Saved the bonus df to {SAVE_PATH}!")

##
# TODO: take a look at how the randomly generated rows were coded!
