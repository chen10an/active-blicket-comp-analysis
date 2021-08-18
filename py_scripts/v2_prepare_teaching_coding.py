# Prepare the teaching examples for coding

##
import pandas as pd
import os
import random
import string
import hashlib

OUTPUT_DIR_PATH = '../ignore/output/v2/'
SAVE_PATH = '../ignore/output/v2/todo_teaching_coding.csv'

##
# load preprocessed teaching data
teaching_df = pd.read_csv(os.path.join(OUTPUT_DIR_PATH, 'quiz_teaching.csv'))

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
# save
coding_df.to_csv(SAVE_PATH, index = False)
print(f"Saved the coding df to {SAVE_PATH}!")
