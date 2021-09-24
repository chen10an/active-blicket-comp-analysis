# Mark whether participants' teaching examples (with coded forms) are matched to the ground truth forms

##
import pandas as pd
import numpy as np
import os
import matplotlib.pyplot as plt
import matplotlib
matplotlib.use('Qt5Agg')

OUTPUT_DIR_PATH = '../ignore/output/v2/'
CODING_DIR_PATH = '../ignore/output/v2/coding/'

coded_files = ['done_teaching_coding_20x-mturk_pilot.csv',
               'done_teaching_coding_micro_1.csv',
               'coder2_done_teaching_coding_micro_1.csv',
               'done_teaching_coding_micro_2-3.csv',
               'coder2_done_teaching_coding_micro_2-3.csv',
               'done_teaching_coding_first209_full.csv',
               'coder2_done_teaching_coding_first209_full.csv'
               ]
print("coded files:", coded_files)
coded_dex_start = int(input("starting dex for choosing from above: "))
coded_dex_end = int(input("ending dex (exclusive) for choosing from above: "))
coded_files = coded_files[coded_dex_start:coded_dex_end]

truth_file = ['quiz_teaching.csv', 'micro_teaching.csv']
print("truth file:", truth_file)
truth_dex = int(input("ONE dex for choosing from above: "))
truth_file = truth_file[truth_dex]

##
# load coded teaching examples
coded_df_list = []
for f in coded_files:
    coded_df_list.append(pd.read_csv(os.path.join(CODING_DIR_PATH, f)))
coded_df = pd.concat(coded_df_list, keys=[i for i in range(len(coded_df_list))])

# load teaching examples with their associated ground truth information (i.e., session_id, training/form, level)
truth_df = pd.read_csv(os.path.join(OUTPUT_DIR_PATH, truth_file))

##
# label every row with a shorthand name for the ground truth form

if truth_file == 'quiz_teaching.csv':
    # for level 1, the shorthand name is just the same as training without the level '1' part
    truth_df.loc[truth_df.level == 1, 'true_short_form'] = truth_df.loc[truth_df.level == 1].training.apply(lambda x: x.replace('1', ''))

    # the level 2 form is always 'c' (deterministic conjunctive)
    truth_df.loc[truth_df.level == 2, 'true_short_form'] = 'c'
    
elif truth_file == 'micro_teaching.csv':
    long_to_shorthand_form = {
        'disj': 'd',
        'noisy_conj': 'nc',
        'conj3': 'cc',
        'noisy_disj': 'nd',
        'conj': 'c',
        'noisy_conj3': 'ncc',
        'participant': 'p'
        }

    truth_df['true_short_form'] = truth_df.apply(lambda row: long_to_shorthand_form[row.true_form], axis=1)
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
        # if the coded form is nan, check if it has been labeled inside/outside (exclusively)
        # XOR:
        assert((row.is_inside or row.is_outside) and (row.is_inside != row.is_outside))
        # if assertion error, diagnose with:
        # coded_df[pd.isnull(coded_df.form) & ~coded_df.is_inside & ~coded_df.is_outside]
        # coded_df[pd.isnull(coded_df.form) & coded_df.is_inside & coded_df.is_outside]
        
        if row.is_inside:
            return 'inside'
        elif row.is_outside:
            return 'outside'
    
    return code_to_shorthand_form[(row.form, row.is_noisy)]

coded_df['coded_short_form'] = coded_df.apply(convert_to_shorthand_form, axis=1)

##
# disagreement ratio when there are multiple coders
num_disagreements = (coded_df.groupby('hash_id').coded_short_form.nunique() > 1).sum()

print(f"Disagreements (with random rows): {num_disagreements}/{len(coded_df.groupby('hash_id'))} = {num_disagreements/len(coded_df.groupby('hash_id'))}")

##
# join on hash id, getting rid of the randomly generated rows
merged_df = truth_df.merge(coded_df, on='hash_id', how='inner')

num_disagreements_no_rand = (merged_df.groupby('hash_id').coded_short_form.nunique() > 1).sum()
print(f"Disagreements (no random rows): {num_disagreements_no_rand}/{len(merged_df.groupby('hash_id'))} = {num_disagreements_no_rand/len(merged_df.groupby('hash_id'))}")

##
BONUS = 0.08  # possible bonus per set/level of teaching questions per coder

merged_df['is_correct'] = False
merged_df.loc[merged_df.coded_short_form == merged_df.true_short_form, 'is_correct'] = True

# column needed for mturk bonusing
merged_df['BonusAmount'] = 0.0
merged_df.loc[merged_df.is_correct, 'BonusAmount'] = BONUS

# view
merged_df[['true_short_form', 'coded_short_form', 'is_correct', 'BonusAmount']]

##
# filter out columns not needed for mturk bonusing
bonus_df = merged_df[['session_id', 'BonusAmount']]

# add up bonus per session/participant
bonus_df = bonus_df.groupby('session_id').sum()

##
# save
save_path = os.path.join(CODING_DIR_PATH, 'bonus_teaching_coding_first209_full.csv')
# bonus_df.to_csv(save_path)
# print(f"Saved the bonus df to {save_path}!")

##
# TODO: take a look at how the randomly generated rows were coded!
