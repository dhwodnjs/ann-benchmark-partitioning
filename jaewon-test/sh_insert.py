import argparse
import numpy as np
import h5py
import time
import psycopg
import pgvector.psycopg
from tqdm import tqdm
from sklearn.decomposition import PCA

def load_and_transform_dataset(data_path):
    # hdf5_filename = "/home/jaewonoh/workspace/ann-benchmark/data/deep-image-96-angular.hdf5"
    hdf5_filename = data_path
    D = h5py.File(hdf5_filename, "r")

    X_train = np.array(D["train"])
    X_test = np.array(D["test"])

    return X_train, X_test

def insert_index(X_train, table_name, port):

    conn = psycopg.connect(host="localhost", user="ann", password="ann", dbname="ann", autocommit=True, port = port)
    pgvector.psycopg.register_vector(conn)
    cur = conn.cursor()

    cur.execute(f"SELECT COUNT(*) FROM {table_name}")
    offset = cur.fetchone()[0]

    # 실행 시간 측정 (DB 연결 시간 제외)
    t0 = time.time()
    # print(f"Inserting data into {table_name} row by row...")
    for i, embedding in tqdm(enumerate(X_train)):
        embedding_str = "[" + ",".join(map(str, embedding)) + "]"
        cur.execute(f"INSERT INTO {table_name} (id, embedding) VALUES (%s, %s)", (i + offset, embedding_str))


    conn.commit()
    build_time = time.time() - t0
    print(f"Inserted {len(X_train)} rows into {table_name} in {build_time:.2f} seconds.")
    return build_time


def sort_by_pca(test, n_components=1, svd_solver="auto"):
    """
    Sort vectors based on their projection onto the first principal component.
    """
    pca = PCA(n_components=n_components, svd_solver=svd_solver)
    projected = pca.fit_transform(test)  # Transform to principal component space
    sorted_indices = np.argsort(projected[:, 0])  # Sort by the first principal component
    return test[sorted_indices]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--size", type=int, required=True, help="Data size")
    parser.add_argument("--ratio", type=int, required=True, help="Data ratio (10%~100%)")
    parser.add_argument("--table_name", type=str, required=True, help="Table name for inserting data")
    parser.add_argument("--data_path", type=str, required=True)
    parser.add_argument("--port", type=str, required=True)
    args = parser.parse_args()

    X_train, X_test = load_and_transform_dataset(args.data_path)

    seed = 42
    np.random.seed(seed)

    X_train = X_train[np.random.choice(X_train.shape[0], args.size, replace=False)]
    sample_size = int(args.size * (args.ratio / 100))

    offset = 151
    X_train_insert = X_train[sample_size+offset:sample_size+offset+50]
    # X_train_insert_pca = sort_by_pca(X_train_insert)

    # ---- Add PCA sorting  ----
    # X_train_sorted = sort_by_pca(X_train)
    # X_train_insert_sorted = X_train_sorted[sample_size:]

    insert_index(X_train_insert, args.table_name, args.port)
    # insert_index(X_train_insert_pca, args.table_name, args.port)
    # insert_index(X_train_insert_sorted, args.table_name, args.port)
