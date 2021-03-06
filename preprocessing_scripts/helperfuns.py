# %%
import os
import json
import pandas as pd
import numpy as np
import jmespath

# mapping used for experiment version 100-mturk
# (this was before I added the condition name to the sent chunks)
ROUTE_TO_CONDITION = {
    '/conditions/0': 'c1_c2_d3',
    '/conditions/1': 'd1_d2_c3',
    '/conditions/2': 'c1_d3',
    '/conditions/3': 'd1_c3'
}

def load_data(experiment_version, data_dir_path='../ignore/data/'):
    """Return a list of dicts (chunks) and df of MTurk worker IDs corresponding to a specific experiment version."""
    with open(os.path.join(data_dir_path, f'chunks_{experiment_version}.json')) as f:
        data_list = json.load(f)

    if experiment_version == '101-mturk':
        # for versions 101, 102, 103, 104, I managed to write all their data to 101 chunks while having their dispatched worker IDs stored in different files...
        id_file_list = [os.path.join(data_dir_path, f'd_mturk_worker_ids_{v}.tsv') for v in ['101-mturk', '102-mturk', '103-mturk', '104-mturk']]
    else: 
        id_file_list = [os.path.join(data_dir_path, f'd_mturk_worker_ids_{experiment_version}.tsv')]
    
    # combine id files if there are several
    dfs = []
    for id_file in id_file_list:
        with open(id_file) as f:
            dfs.append(pd.read_csv(f, sep='\t'))

    id_df = pd.concat(dfs, ignore_index=True)

    return data_list, id_df

def get_end_id_bonus_dfs(experiment_version, data_dir_path):
    """Get useful dataframes from experiment data files.

    Load different experiment data files and join MTurk workerIds with their associated chunks data (including their bonus amounts).

    :param experiment_version: Semantic version of the Mturk experiment without dots between major, minor, and patch numbers, e.g. '100-mturk' for the full sematic version '1.0.0-mturk'."
    :param data_dir_path: path to directory where all chunks and workerId data are stored.

    :return: tuple of (chunks_df, workerid_df, bonus_df)
    """
    data_list, id_df = load_data(experiment_version=experiment_version, data_dir_path=data_dir_path)

    # parse json to find relevant score data for calculating bonuses
    end = jmespath.search("[?seq_key=='End'].{sessionId: sessionId, route: route, condition_name: condition_name, end_time: timestamp, score: score, max_score: max_score, bonus_per_q: bonus_per_q, total_bonus: total_bonus}", data_list)
    end_df = pd.DataFrame(end)
    end_df.reset_index(inplace=True, drop=True)

    if experiment_version == '100-mturk':
        # I did not put bonus amounts into the experiment data yet, so here are the posthoc calculations
        end_df.loc[:, 'condition'] = end_df.route.apply(lambda x: x[-1]).astype(int)
        end_df.loc[:, 'bonus_per_q'] = 0.05
        end_df.loc[end_df.condition > 1, 'bonus_per_q'] = 0.075
        end_df.loc[:, 'total_bonus'] = end_df.apply(lambda x: x.score * x.bonus_per_q, axis=1)

    # join experiment data with mturk ids and extract bonuses
    joined_df = end_df.join(id_df.set_index('session_id'), on='sessionId', how='inner')
    bonus_df = joined_df[['participant_id', 'total_bonus']]
    bonus_df = bonus_df.rename(columns={'participant_id': 'WorkerId', 'total_bonus': 'BonusAmount'})
    bonus_df.loc[:, 'Reason'] = 'Correctly answering quiz questions about blickets and the blicket machine.'

    # round bonus to 2 decimal and turn into string to conform to the mturk API's send_bonus syntax
    bonus_df.loc[:, 'BonusAmount'] = bonus_df.BonusAmount.round(2).astype(str)

    return (end_df, id_df, bonus_df)

def load_mturk_batch_df(batch_dir_path):
    """Return one dataframe from a directory of batch csvs downloaded from MTurk's batch review UI
    """
    batch_file_paths = [os.path.join(batch_dir_path, f) for f in os.listdir(batch_dir_path) if os.path.isfile(os.path.join(batch_dir_path, f))]

    batch_dfs = []
    for f_path in batch_file_paths:
        with open(f_path) as f:
            batch_dfs.append(pd.read_csv(f))

    all_batch_df = pd.concat(batch_dfs)

    # check no repeated workers
    if (len(all_batch_df.WorkerId.unique()) != all_batch_df.shape[0]):
        print("ohno these batches have repeated WorkerIds")

    print(f"There are {all_batch_df.shape[0]} unique workers in these batches.")
    print("-----\n")

    return all_batch_df

def get_quiz_df(experiment_version, data_dir_path):
    """Return a dataframe containing quiz data for activation prediction questions and is-a-blicket questions, indexed by (condition, quiz level, session ID)"""

    # load chunks
    data_list, _ = load_data(experiment_version=experiment_version, data_dir_path=data_dir_path)

    # query chunks json for quiz-related data
    quiz = jmespath.search("[?seq_key=='End'].{sessionId: sessionId, end_time: timestamp, route: route, condition_name: condition_name, score: score, max_score: max_score, is_trouble: is_trouble, quiz_data: quiz_data, blicket_answers: quiz_data.*.blicket_answer_combo | [*].bitstring}", data_list)

    # prepare a dicts to converted into dataframes indexed by (experiment condition, quiz level, session ID)
    # separate prediction vs blicket df creation because they have different datatypes: int vs string
    pred_reshaped_dict = {}
    blicket_reshaped_dict = {}
    for session in quiz:
        # don't consider sessions before this time because the chunk fields were still in development and no real participants had done the experiment yet
        if pd.to_datetime(session['end_time'], unit='ms') <= pd.Timestamp('2020-12-29 17:12:28'):
            continue

        # skip sessions that probably encountered technical issues
        if session['is_trouble']:
            continue

        if experiment_version == '100-mturk':
            # this was before I added the condition name to the sent chunks
            condition_name = ROUTE_TO_CONDITION[session['route']]
        else:
            condition_name = session['condition_name']

        # don't consider sessions where I haven't implemented condition_name
        # (except for experiment 100-mturk)
        if condition_name is None:
            continue

        # consider different quiz levels for different experiment conditions
        level_nums = [1, 3]

        if len(condition_name.split('_')) == 3:
            level_nums.append(2)
            
            # sorting is especially important for making sure the index i below matches blicket answer bitstrings to the correct level number:
            level_nums.sort()
        else:
            # there should only be 3 or 2 parts in a condition name
            assert len(condition_name.split('_')) == 2    

        for i in range(len(level_nums)):
            l_num = level_nums[i]
            # prep the index for the resulting dataframe
            index = (condition_name, l_num, session['sessionId'])  # (experiment condition, quiz level, session ID)

            level_dict = session['quiz_data'][f'level_{l_num}']
            activation_score = level_dict['activation_score']
            answered_correctly = np.equal(level_dict['activation_answer_groups'], level_dict['correct_activation_answers'])
            total_correct = np.sum(answered_correctly)

            # sanity check that the total score calculated from individual questions is the same as the recorded total score for activation prediction questions
            assert total_correct == level_dict['activation_score']

            # prep cols for the resulting dataframe
            pred_reshaped_dict[index] = np.concatenate([answered_correctly, [total_correct]])
            blicket_reshaped_dict[index] = [session['blicket_answers'][i]]

    # int df
    pred_df = pd.DataFrame(pred_reshaped_dict).T
    pred_df.index.set_names(['condition', 'level', 'session_id'], inplace=True)
    pred_df.columns = ['q1_point', 'q2_point', 'q3_point', 'q4_point', 'q5_point', 'q6_point', 'q7_point', 'total_points']

    # str df
    blicket_df = pd.DataFrame(blicket_reshaped_dict).T
    blicket_df.index.set_names(['condition', 'level', 'session_id'], inplace=True)
    blicket_df.columns = ['blicket_answer']

    # join pred and blicket dfs together on their common index
    quiz_df = pred_df.join(blicket_df, how='inner')

    print(f"{experiment_version}:")
    # there should only be quiz levels 1,2,3
    assert set(quiz_df.index.get_level_values('level').unique()) == set([1, 2, 3])
    print("Passed: we have exactly quiz levels 1, 2, 3.")
    print(f"Unique experiment conditions: {list(quiz_df.index.get_level_values('condition').unique())}")
    print(f"Num unique sessions (recorded at End component, where is_trouble=False): {len(quiz_df.index.get_level_values('session_id').unique())}")
    print("-----\n")

    # put in the correct blicket answers
    # level 1
    quiz_df.loc[pd.IndexSlice[['d1_d2_d3', 'd1_d3', 'd1_d2_c3', 'd1_c3'], 1, :], 'correct_answer'] = '100'  # 1 blicket for disjunctive level 1
    quiz_df.loc[pd.IndexSlice[['c1_c2_c3', 'c1_c3', 'c1_c2_d3', 'c1_d3'], 1, :], 'correct_answer'] = '110'  # 2 blickets for conjunctive level 1
    # level 2
    quiz_df.loc[pd.IndexSlice[:, 2, :], 'correct_answer'] = '111000'  # 6 blocks, 3 blickets for both disj and conj
    # level 3
    quiz_df.loc[pd.IndexSlice[:, 3, :], 'correct_answer'] = '111100000'  # 9 blocks, 4 blickets for both disj and conj

    # add blicket metrics into the dataframe
    metrics_df = quiz_df.apply(lambda df: get_blicket_metrics(participant_ans=df.blicket_answer, correct_ans=df.correct_answer, return_series=True), axis=1)
    quiz_df = quiz_df.join(metrics_df)

    return quiz_df

def get_filtered_id_df(experiment_version, data_dir_path):
    """Return a df with valid participant IDs and session IDs.
    
    The returned df can then be used to filter other dfs for valid participants and sessions, e.g.
    `df.merge(filtered_id_df, on='session_id', how='inner')`
    """

    _, id_df = load_data(experiment_version=experiment_version, data_dir_path=data_dir_path)

    print(f"{experiment_version}:")
    print(f"Number of rows in the raw participant ID file: {id_df.shape[0]}")

    # filter out...
    # ... all of my "test" worker IDs and any empty (na) IDs
    filtered_df = id_df[~id_df.participant_id.str.contains('test', case=False, regex=False, na=True)]
    # ... any empty string IDs
    filtered_df = filtered_df[filtered_df.participant_id != '']
    # ... unsuccessful session IDs (participant probably tried the link several times)
    filtered_df = filtered_df[filtered_df.session_id != 'NO_SESSION_ID']

    print(f"Number unique filtered participant IDs: {len(filtered_df.participant_id.unique())}")
    print(f"Number total filtered participant IDs: {len(filtered_df.participant_id)}")
    # for 101-mturk: num unique filtered is one less than the total, which is ok because my digging shows one participant was glitchily dispatched twice (two session ids with the same dispatch time)
    print("-----\n")

    return filtered_df

def get_blicket_metrics(participant_ans, correct_ans, return_series=False):
    """Return [accuracy, precision, recall] for comparing the participant's blicket answer to the correct answer, where answers are expressed as a bitstring"""

    # check that inputs are strings
    assert isinstance(participant_ans, str)
    assert isinstance(correct_ans, str)

    pred = np.array(list(participant_ans)).astype(bool)
    true = np.array(list(correct_ans)).astype(bool)
    accuracy = (pred == true).sum()/len(true)

    num_real_positives = true.sum()  # true positives + false positives
    num_guessed_tp = ((pred == true) & true).sum()  # true positives that the participant managed to guess
    num_guessed_positives = pred.sum()  # true positives + false positives

    if num_real_positives == 0:
        recall = None
    else:
        recall = num_guessed_tp/num_real_positives
    
    if num_guessed_positives == 0:
        precision = None
    else:
        precision = num_guessed_tp/num_guessed_positives

    if return_series:
        return pd.Series([accuracy, recall, precision], index=['accuracy', 'recall', 'precision'])
    else:
        return (accuracy, recall, precision)
# some sanity checking unit tests
assert get_blicket_metrics(participant_ans='110', correct_ans='100') == (2/3, 1, 1/2)
assert get_blicket_metrics(participant_ans='111', correct_ans='100') == (1/3, 1, 1/3)
assert get_blicket_metrics(participant_ans='011', correct_ans='100') == (0, 0, 0)
assert get_blicket_metrics(participant_ans='000', correct_ans='100') == (2/3, 0, None)
assert get_blicket_metrics(participant_ans='000', correct_ans='000') == (1, None, None)

# %%
def get_full_df(data_type, data_dir_path='../ignore/data/'):
    """Return a filtered and concatenated dataframe across all participants and experiment versions.
    
    For data type "quiz":
    The dataframe contains both activation prediction questions and is-a-blicket questions, indexed by (condition, quiz level, session ID).

    For data type "task_3":
    The dataframe contains task/intervention data in phase 3 only, indexed by (condition, session ID, timestamp). 
    """

    assert data_type in ['quiz', 'task_1', 'task_2', 'task_3']

    if data_type == 'quiz':
        get_df = lambda v: get_quiz_df(experiment_version=v, data_dir_path=data_dir_path)
    elif data_type.startswith('task_'):
        level = int(data_type.split('_')[1])
        get_df = lambda v: get_task_df(experiment_version=v, level=level, data_dir_path=data_dir_path)

    df0 = get_df('100-mturk')
    df1 = get_df('101-mturk')

    # load valid participant IDs
    fid0_df = get_filtered_id_df(experiment_version='100-mturk', data_dir_path=data_dir_path)
    fid1_df = get_filtered_id_df(experiment_version='101-mturk', data_dir_path=data_dir_path)

    # get intersection of sessions with activation prediction answers and sessions with valid participant IDs
    fdf0 = df0.reset_index().merge(fid0_df, on='session_id', how='inner')
    fdf1 = df1.reset_index().merge(fid1_df, on='session_id', how='inner')
    # sanity checks
    for key, df in {'Filtered 100-mturk quiz data': fdf0, 'Filtered 101-mturk quiz data': fdf1}.items():
        print(f"{key}:")
        assert all(df.groupby('session_id').condition.nunique() == 1)
        print("Passed: Each session only has 1 experiment condition.")
        assert len(df.participant_id.unique()) == len(df['session_id'].unique())
        print(f"Passed: Unique participant IDs and unique session IDs have the same count ({len(df.participant_id.unique())}).")
        print("\n")
        # 101-mturk: the full task (phase 3) data has 3 less participants than the full quiz (all phases) data
        # because 3 participants did not try any interventions/combos in phase 3 :(

    # concat data from both experiment versions
    f_all_df = pd.concat([fdf0, fdf1])

    if data_type == 'quiz':
        f_all_df = f_all_df.set_index(['condition', 'level', 'session_id'])
    elif data_type.startswith('task_'):
        f_all_df = f_all_df.set_index(['condition', 'session_id', 'timestamp'])

    print(f"The resulting filtered and concatenated quiz dataframe has {len(f_all_df.index.get_level_values('session_id').unique())} unique sessions/participants.")
    print("-----\n")

    return f_all_df

# %%
def get_task_df(experiment_version, level, data_dir_path='../ignore/data/'):
    """Get intervention (block combinations) data in level/phase 1 or 3"""

    # load chunks
    data_list, _ = load_data(experiment_version=experiment_version, data_dir_path=data_dir_path)

    # query chunks json for task-related data
    task = jmespath.search(f"[?seq_key=='End'].{{sessionId: sessionId, end_time: timestamp, route: route, condition_name: condition_name, score: score, max_score: max_score, is_trouble: is_trouble, task_data_{level}: task_data.level_{level}.all_combos, blicket_answer_{level}: quiz_data.level_{level}.blicket_answer_combo.bitstring}}", data_list)

    # start creating rows for the resulting dataframe
    rows = []
    for session in task:
        # for the second level, don't consider short conditions that do not have a second level
        if level == 2 and session['task_data_2'] is None:
            continue
        
        # don't consider sessions before this time because the chunk fields were still in development and no real participants had done the experiment yet
        if pd.to_datetime(session['end_time'], unit='ms') <= pd.Timestamp('2020-12-29 17:12:28'):
            continue

        # skip sessions that probably encountered technical issues
        if session['is_trouble']:
            continue

        if experiment_version == '100-mturk':
            # this was before I added the condition name to the sent chunks
            condition_name = ROUTE_TO_CONDITION[session['route']]
        else:
            condition_name = session['condition_name']

        # don't consider sessions where I haven't implemented condition_name
        # (except for experiment 100-mturk)
        if condition_name is None:
            continue

        # prep the index for the resulting dataframe
        partial_index = [condition_name, session['sessionId']]

        timestamps = jmespath.search("[*].timestamp", session[f'task_data_{level}'])
        combos = jmespath.search("[*].bitstring", session[f'task_data_{level}'])
        
        for i in range(len(timestamps)):
            full_index = partial_index + [timestamps[i]]
            
            # use numpy to change type to int
            # then change back list so we can have multi-type rows
            current_combo = np.array(list(combos[i])).astype(int)
            current_combo = list(current_combo)

            rows.append(full_index + current_combo + [session[f'blicket_answer_{level}']])

    num_blocks = level*3  # 3 blocks in l1, 6 in l2, 9 in l3
    task_df = pd.DataFrame(rows, columns=
        ['condition', 'session_id', 'timestamp'] +
        [f'id_{i}' for i in range(num_blocks)] +
        ['blicket_answer'])
    
    task_df.set_index(['condition', 'session_id', 'timestamp'], inplace=True)

    return task_df
# %%
