# filter out all of my testing data and other misformatted data so that we're only left with good data containing real (MTurk) participants who successfully completed the experiment

## %%
import os
import json
import pandas as pd
import jmespath

DATA_DIR_PATH = '../ignore/data/'

option_dex = int(input("0 for 200-mturk; 1 for 20x-mturk-micro"))
chunks_filename = ['chunks_200-mturk.json', 'chunks_20x-mturk-micro.json'][option_dex]
ids_filename = ['d_mturk_worker_ids_200-mturk.tsv', 'd_mturk_worker_ids_20x-mturk-micro.tsv'][option_dex]
save_path = ['../ignore/output/v2/good_endings.json', '../ignore/output/v2/good_endings_micro.json'][option_dex]

## %%
# Get a list of dicts (chunks) and df of MTurk worker IDs for v2
with open(os.path.join(DATA_DIR_PATH, chunks_filename)) as f:
    data_list = json.load(f)

with open(os.path.join(DATA_DIR_PATH, ids_filename)) as f:
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

print(f"Number of chunks that match to the filtered participant IDs: {len(filtered_chunks)}")
## %%
# finally get just the good ending chunks, where participants did not reach a trouble ending by failing comprehension or captcha checks
good_endings = jmespath.search("[?seq_key=='End'] | [?!is_trouble]", filtered_chunks)

print(f"Final number of chunks that are also not trouble: {len(good_endings)}")

##%%
with open(save_path, 'w') as f:
    json.dump(good_endings, f)
print(f"Saved v2 good ending chunks to {save_path}!")
