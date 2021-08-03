# filter out all of my testing data and other misformatted data so that we're only left with good data containing real (MTurk) participants who successfully completed the experiment

## %%
import os
import json
import pandas as pd
import jmespath

DATA_DIR_PATH = '../ignore/data/'
SAVE_PATH = '../ignore/output/v2_good_endings.json'

## %%
# Get a list of dicts (chunks) and df of MTurk worker IDs for v2
with open(os.path.join(DATA_DIR_PATH, 'chunks_200-mturk.json')) as f:
    data_list = json.load(f)

with open(os.path.join(DATA_DIR_PATH, 'd_mturk_worker_ids_200-mturk.tsv')) as f:
    id_df = pd.read_csv(f, sep='\t')

print(f"Number of rows in the raw participant ID file: {id_df.shape[0]}")

## %%
# filter out...
# ... all of my "test" worker IDs and any empty (na) IDs
filtered_df = id_df[~id_df.participant_id.str.contains('test', case=False, regex=False, na=True)]
# ... any IDs that are too short (I'm using 10 to be safe; shortest mturk IDs I've seed are length 13)
filtered_df = filtered_df[filtered_df.participant_id.str.len() > 10]
# ... any empty string IDs
filtered_df = filtered_df[filtered_df.participant_id != '']
# ... unsuccessful session IDs (participant probably tried the link several times)
filtered_df = filtered_df[filtered_df.session_id != 'NO_SESSION_ID']

print(f"Number unique filtered participant IDs: {len(filtered_df.participant_id.unique())}")
print(f"Number total filtered participant IDs: {len(filtered_df.participant_id)}")

## %%
# get only the good chunks/dicts corresponding to the session IDs in filtered_df
filtered_chunks = []
for chunk in data_list:
    if filtered_df.session_id.str.contains(chunk['sessionId']).any():
        filtered_chunks.append(chunk)

## %%
# finally get just the good ending chunks, where participants did not reach a trouble ending by failing comprehension or captcha checks
good_endings = jmespath.search("[?seq_key=='End'] | [?!is_trouble]", filtered_chunks)

##%%
with open(SAVE_PATH, 'w') as f:
    json.dump(good_endings, f)
print(f"Saved v2 good ending chunks to {SAVE_PATH}!")
