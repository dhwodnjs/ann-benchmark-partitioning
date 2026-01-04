import argparse
import numpy as np
import h5py
import time
import psycopg
import pgvector.psycopg


def load_and_transform_dataset(data_path):
    hdf5_filename = data_path
    D = h5py.File(hdf5_filename, "r")

    X_train = np.array(D["train"])
    X_test = np.array(D["test"])
    # print(f"Loaded dataset: {X_train.shape[0]} samples, {X_train.shape[1]} dimensions")
    return X_train, X_test


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--size", type=int, required=True, help="Data size")
    parser.add_argument("--data_path", type=str, required=True)
    parser.add_argument("--table_name", type=str, required=True, help="Table name for storing index")
    args = parser.parse_args()

    X_train, X_test = load_and_transform_dataset(args.data_path)

    seed = 42
    np.random.seed(seed)

    X_train = X_train[np.random.choice(X_train.shape[0], args.size, replace=False)]

    np.save(f"{args.table_name}.npy", X_train)


