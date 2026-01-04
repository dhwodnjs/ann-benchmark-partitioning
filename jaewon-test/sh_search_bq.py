import argparse
import numpy as np
import h5py
import psycopg
import pgvector.psycopg
from tqdm import tqdm
from typing import Tuple, List, Union
import time


def load_and_transform_dataset(data_path) -> Tuple[
    Union[np.ndarray, List[np.ndarray]],
    Union[np.ndarray, List[np.ndarray]],
    str,
    Union[np.ndarray, List[np.ndarray]]]:
    """Loads and transforms the dataset.

    Args:
        hdf5_filename (str): The path to the dataset file.

    Returns:
        Tuple: Transformed datasets.
    """

    # hdf5_filename = "/home/jaewonoh/workspace/ann-benchmark/data/deep-image-96-angular.hdf5"
    hdf5_filename = data_path
    D = h5py.File(hdf5_filename, "r")

    X_train = np.array(D["train"])
    X_test = np.array(D["test"])
    distance = D.attrs["distance"]

    neighbor = np.array(D["neighbors"])


    # print(f"Loaded dataset: {X_train.shape[0]} samples, {X_train.shape[1]} dimensions")
    # print(f"Loaded {len(X_test)} queries")

    return X_train, X_test, distance, neighbor


def query(cur, table_name: str, v: np.ndarray, n: int):
    """Performs a vector similarity search.

    Args:
        cur (psycopg.Cursor): The PostgreSQL cursor.
        table_name (str): The table name.
        v (np.ndarray): The query vector.
        n (int): The number of nearest neighbors to retrieve.

    Returns:
        List[int]: The list of nearest neighbor IDs.
    """
    query = f"SET LOCAL hnsw.ef_search = 200;"
    # cur.execute(query)
    query = f"SELECT id FROM {table_name} ORDER BY binary_quantize(embedding)::bit(512) <~> binary_quantize(%s) LIMIT %s"
    cur.execute(query, (v, n), binary=True, prepare=True)


    # query = f"""
    # SELECT id FROM (
    #     SELECT *
    #     FROM {table_name}
    #     ORDER BY binary_quantize(embedding)::bit(512)
    #             <~> binary_quantize(%s)
    #     LIMIT 200
    # )
    # ORDER BY embedding <=> %s
    # LIMIT %s;
    # """
    #
    # cur.execute(query, (v, v, n), binary=True, prepare=True)
    #
    # # 1) EXPLAIN 출력
    # explain_query = "EXPLAIN (ANALYZE) " + query
    # cur.execute(explain_query, (v, v, n), binary=True, prepare=True)
    # for (line,) in cur.fetchall():
    #     print(line)

    # # 2) 실제 결과 리턴 (기존과 동일)
    # cur.execute(query, (v, v, n), binary=True, prepare=True)
    # return [id for (id,) in cur.fetchall()]

    # query = f"""
    #     SELECT id FROM (
    #         SELECT *
    #         FROM {table_name}
    #         ORDER BY binary_quantize(embedding)::bit(512)
    #                 <~> binary_quantize(%s)
    #         LIMIT 50
    #     )
    #     ORDER BY embedding <=> %s LIMIT %s;
    # """
    #
    #
    return [id for id, in cur.fetchall()]

def get_page_stats(cur, table_name: str):
    """Fetches page read/hit stats for the index."""
    cur.execute(f"""
        SELECT relname AS index_name, idx_blks_hit, idx_blks_read,
               ROUND(100.0 * idx_blks_hit / NULLIF(idx_blks_hit + idx_blks_read, 0), 2) AS index_hit_ratio
        FROM pg_statio_user_indexes
        WHERE relname = '{table_name}'
        ORDER BY index_hit_ratio DESC;
    """)
    return cur.fetchall()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--table_name", type=str, required=True, help="Table name for search")
    parser.add_argument("--data_path", type=str, required=True)
    parser.add_argument("--port", type=str, required=True)
    parser.add_argument("--num", type=int, required=True)
    args = parser.parse_args()

    # Connect to PostgreSQL
    conn = psycopg.connect(host="localhost", user="ann", password="ann", dbname="ann", autocommit=True, port = args.port)
    pgvector.psycopg.register_vector(conn)
    cur = conn.cursor()

    # Load dataset
    X_train, X_test, distance, neighbor = load_and_transform_dataset(args.data_path)


    seed = 42
    np.random.seed(seed)

    X_test = X_test[np.random.choice(X_test.shape[0], 1000, replace=False)]


    # Perform search for each query
    t0 = time.time()

    if args.num == 1:
        query(cur, args.table_name, X_test[10], 5)
    else:

        results = [query(cur, args.table_name, x, 5) for x in tqdm(X_test)]
        # print(neighbor[:][:5])
        # avg_overlap = np.mean([
        #     len(set(results[i]) & set(neighbor[i][:5]))
        #     for i in range(len(results))
        # ])
        #
        # recall_at_5 = avg_overlap / 5
        # print(recall_at_5)


        search_time = time.time() - t0  # 종료 시간 기록
        print(f"Search completed in {search_time:.2f} seconds.")

        print(results[:10])
