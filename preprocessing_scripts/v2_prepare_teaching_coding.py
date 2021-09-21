# Prepare the teaching examples for coding

##
import pandas as pd
import numpy as np
import os
import random
import string
import hashlib

# ** FILL OUT THIS CELL BEFORE RUNNING**
OUTPUT_DIR_PATH = '../ignore/output/v2/'
DONE_FILES = ['coding/done_teaching_coding_micro_1.csv', 'coding/done_teaching_coding_micro_2-3.csv', 'coding/done_teaching_coding_20x-mturk_pilot.csv']
DONE_FILES = [os.path.join(OUTPUT_DIR_PATH, f) for f in DONE_FILES]

# option_dex = int(input("0 for 200-mturk; 1 for 20x-mturk-micro"))
option_dex = 0
teaching_filename = ['quiz_teaching.csv', 'micro_teaching.csv'][option_dex]
save_path = ['../ignore/output/v2/todo_teaching_coding_first209.csv', '../ignore/output/v2/todo_teaching_coding_micro_2-3.csv'][option_dex]

# don't process participants after this timestamp; this is for separating out which participants need more urgent coding
EARLIEST_ENDTIME = pd.Timestamp('2021-09-15 00:00:00')

##
# **JUST RUN THE BELOW CELLS**

# load preprocessed teaching data
teaching_df = pd.read_csv(os.path.join(OUTPUT_DIR_PATH, teaching_filename))

# filter out hashes that have already been coded
done_sub_dfs = []
for f in DONE_FILES:
    done_sub_dfs.append(pd.read_csv(f))

done_df = pd.concat(done_sub_dfs, ignore_index=True)
done_hash_ids = done_df.hash_id
# note: there will be overlap in the randomly generated hash_ids across files because they all use the same seed
teaching_df = teaching_df[~teaching_df.hash_id.isin(done_hash_ids)]

# filter out based on earliest endtime
teaching_df = teaching_df[pd.to_datetime(teaching_df.end_time, unit='ms') <= EARLIEST_ENDTIME]

print(f"{teaching_df.shape[0]} real teaching example sets to code.")

##
def make_random_hash_id():
    # generate a random session_id-like string: join random choices of upper/lower letters and digits, totaling length 32
    random_legible_id = ''.join(random.choices(string.ascii_letters + string.digits, k=32))

    # encode and hash
    encoding = random_legible_id.encode()
    return hashlib.sha256(encoding).hexdigest()

##
def make_random_ex(num_blocks):
    # generate a random example-like string: join random choices of '*'/'.', totaling length num_blocks, then append a random choice of '+'/'-' at the end
    random_ex = ''.join(random.choices('*.', k=num_blocks))
    random_ex += ' ' + random.choice('+-')
    return random_ex
    
##
# generate random rows, each with 5 blickets/nonblickets/response examples and a hash id

random.seed(0)  # reproducible

# initialize df to be used for coding
coding_cols = ['hash_id'] + [f'ex_{i}' for i in range(5)]
coding_df = teaching_df[coding_cols]

original_num_rows = teaching_df.shape[0]

# for each of 3-block and 6-block, make random examples numbering 10% of the original number of rows
num_random_rows = int(0.1*original_num_rows)  # int rounds down
random_rows = []
for i in range(num_random_rows):
    random_3block_row = pd.DataFrame([[make_random_hash_id()] + [make_random_ex(3) for i in range(5)]], columns=coding_cols)
    random_rows.append(random_3block_row)

    random_6block_row = pd.DataFrame([[make_random_hash_id()] + [make_random_ex(6) for i in range(5)]], columns=coding_cols)
    random_rows.append(random_6block_row)

print(f"Made {len(random_rows)} random rows")
    
# add random rows to the coding df
coding_df = pd.concat([coding_df] + random_rows, ignore_index=True)

# check no collision between hash_ids (very unlikely that the randomly generated hash ids should produce duplicates)
assert(len(coding_df.hash_id.unique()) == coding_df.shape[0])

# shuffle order of rows
coding_df = coding_df.sample(frac=1, ignore_index=True, random_state=0)  # with seed
    
##
# sort examples so that blickets come first, then nonblickets, then response

def sort_ex(ex):
    # takes in a single example/string, like '**. +'
    num_blickets = ex.count('*')
    num_nonblickets = ex.count('.')
    machine_response = ex[-1]

    return '*'*num_blickets + '.'*num_nonblickets + ' ' + machine_response

ex_cols = [f'ex_{i}' for i in range(5)]
for col in ex_cols:
    coding_df[col] = coding_df[col].apply(sort_ex)

##
# sort all coding examples (within each row, not affecting the shuffled row order) and then join into one string in one column
coding_df['sorted_all_ex'] = coding_df[[f'ex_{i}' for i in range(5)]].apply(np.sort, axis=1).apply(' | '.join)

##
# save full coding_df that can be used to match sorted_all_ex to hash_ids
full_save_path = save_path.split('.csv')[0] + '_full.csv'
coding_df.to_csv(full_save_path, index = False)
print(f"Saved the the full coding df (for matching sorted_all_ex to hash_id) to {full_save_path}!")

##
unique_coding_df = coding_df.drop_duplicates(subset='sorted_all_ex').rename(columns={"hash_id": "first_hash_id"})  # only first occurrence is kept for each set of duplicates

print(f"After sorting each set of examples, the unique number of example sets (i.e., rows) to code are: {unique_coding_df.shape[0]}")

##
# save
unique_coding_df.to_csv(save_path, index = False)
print(f"Saved the unique coding df (sorted_all_ex) to {save_path}!")
