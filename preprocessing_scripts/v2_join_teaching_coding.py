# For the full experiment 2 (not micro, not pilot), join the unique coded unique examples with the full set of hash ids

##
import pandas as pd
import numpy as np
import os

CODING_DIR_PATH = '../ignore/output/v2/coding/'

# contains all hash ids with their possibly duplicate example sets
FULL_FILE = 'todo_teaching_coding_first209_full.csv'

# contains only the first hash ids corresponding to unique example sets
CODED_FILES = [
    'done_teaching_coding_first209.csv',
    'coder2_done_teaching_coding_first209.csv'
]

##
full_df = pd.read_csv(os.path.join(CODING_DIR_PATH, FULL_FILE))  # all hash ids with their possibly duplicate teaching examples

for f in CODED_FILES:
    coded_df = pd.read_csv(os.path.join(CODING_DIR_PATH, f))  # unique teaching examples that have been coded

    # join on the teaching example string and drop duplicate cols
    merged_df = full_df.merge(coded_df, on='sorted_all_ex', how='inner', suffixes=("_x", None))
    merged_df = merged_df.drop(columns=[x for x in merged_df.columns if x.endswith("_x")])
    assert(merged_df.shape[0] == full_df.shape[0])

    # save full coding_df that can be used to match sorted_all_ex to hash_ids
    full_save_path = os.path.join(CODING_DIR_PATH, f.split('.csv')[0] + '_full.csv')
    merged_df.to_csv(full_save_path, index = False)
    print(f"Saved the the full (with all hash ids) coded df to {full_save_path}!")


