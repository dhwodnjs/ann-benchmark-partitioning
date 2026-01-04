import argparse
import numpy as np
import h5py
import time
import psycopg
import pgvector.psycopg
from sklearn.decomposition import PCA

def load_and_transform_dataset(data_path):
    # hdf5_filename = "/home/jaewonoh/workspace/ann-benchmark/data/deep-image-96-angular.hdf5"
    hdf5_filename = data_path
    D = h5py.File(hdf5_filename, "r")

    X_train = np.array(D["train"])
    X_test = np.array(D["test"])

    # print(f"Loaded dataset: {X_train.shape[0]} samples, {X_train.shape[1]} dimensions")
    return X_train, X_test

def build_index(X_train, table_name, port):


    conn = psycopg.connect(host="localhost", user="ann", password="ann", dbname="ann", autocommit=True, port = port)
    pgvector.psycopg.register_vector(conn)
    cur = conn.cursor()

    build_time = 0


    # 테이블 존재 여부 확인
    cur.execute(f"SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = %s)", (table_name,))
    table_exists = cur.fetchone()[0]

    if not table_exists:
        # 테이블 생성
        cur.execute(f"CREATE TABLE {table_name} (id int, embedding vector({X_train.shape[1]}))")
        cur.execute(f"ALTER TABLE {table_name} ALTER COLUMN embedding SET STORAGE PLAIN")

        # 데이터 삽입 (COPY)
        with cur.copy(f"COPY {table_name} (id, embedding) FROM STDIN WITH (FORMAT BINARY)") as copy:
            copy.set_types(["int4", "vector"])
            for i, embedding in enumerate(X_train):
                copy.write_row((i, embedding))
    else:
        print(f"Table {table_name} already exists. Skipping data insertion.")

    # 인덱스 존재 여부 확인
    cur.execute(f"SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = %s AND indexname = %s)",
                (table_name, f"{table_name}_embedding_idx"))
    index_exists = cur.fetchone()[0]

    if not index_exists:
        t0 = time.time()
        cur.execute(f"CREATE INDEX ON {table_name} USING hnsw (embedding vector_cosine_ops) WITH (m = 24, ef_construction = 200);")

        build_time = time.time() - t0
        print(f"Built index on {table_name} in {build_time:.2f} seconds")
    else:
        print(f"Index already exists on {table_name}. Skipping index creation.")

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
    parser.add_argument("--table_name", type=str, required=True, help="Table name for storing index")
    parser.add_argument("--data_path", type=str, required=True)
    parser.add_argument("--port", type=str, required=True)
    args = parser.parse_args()

    X_train, X_test = load_and_transform_dataset(args.data_path)

    seed = 42
    np.random.seed(seed)

    X_train = X_train[np.random.choice(X_train.shape[0], args.size, replace=False)]

    sample_size = int(args.size * (args.ratio / 100))

    # ---- Add PCA sorting  ----
    X_train_sorted = sort_by_pca(X_train)


    X_train_build = X_train[:sample_size]
    X_train_build_sorted = X_train_sorted[:sample_size]


    build_index(X_train_build, args.table_name, args.port)
    # build_index(X_train_build_sorted, args.table_name, args.port)
