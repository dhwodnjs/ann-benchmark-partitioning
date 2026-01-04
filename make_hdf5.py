import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
import numpy
import h5py
from ann_benchmarks.algorithms.bruteforce.module import BruteForceBLAS

data_path = "/home/jaewonoh/workspace/data/deep-image-96-angular.hdf5"
size = 100000



def write_output(train: numpy.ndarray, test: numpy.ndarray, fn: str, distance: str, point_type: str = "float", count: int = 100) -> None:
    """
    Writes the provided training and testing data to an HDF5 file. It also computes
    and stores the nearest neighbors and their distances for the test set using a
    brute-force approach.

    Args:
        train (numpy.ndarray): The training data.
        test (numpy.ndarray): The testing data.
        filename (str): The name of the HDF5 file to which data should be written.
        distance_metric (str): The distance metric to use for computing nearest neighbors.
        point_type (str, optional): The type of the data points. Defaults to "float".
        neighbors_count (int, optional): The number of nearest neighbors to compute for
            each point in the test set. Defaults to 100.
    """

    with h5py.File(fn, "w") as f:
        f.attrs["type"] = "dense"
        f.attrs["distance"] = distance
        f.attrs["dimension"] = len(train[0])
        f.attrs["point_type"] = point_type
        print(f"train size: {train.shape[0]} * {train.shape[1]}")
        print(f"test size:  {test.shape[0]} * {test.shape[1]}")
        f.create_dataset("train", data=train)
        f.create_dataset("test", data=test)

        # Create datasets for neighbors and distances
        neighbors_ds = f.create_dataset("neighbors", (len(test), count), dtype=int)
        distances_ds = f.create_dataset("distances", (len(test), count), dtype=float)

        # Fit the brute-force k-NN model
        bf = BruteForceBLAS(distance, precision=train.dtype)
        bf.fit(train)

        for i, x in enumerate(test):
            if i % 1000 == 0:
                print(f"{i}/{len(test)}...")

            # Query the model and sort results by distance
            res = list(bf.query_with_distances(x, count))
            res.sort(key=lambda t: t[-1])

            # Save neighbors indices and distances
            neighbors_ds[i] = [idx for idx, _ in res]
            distances_ds[i] = [dist for _, dist in res]


"""
param: train and test are arrays of arrays of indices.
"""


def load_and_transform_dataset(data_path):
    # hdf5_filename = "/home/jaewonoh/workspace/ann-benchmark/data/deep-image-96-angular.hdf5"
    hdf5_filename = data_path
    D = h5py.File(hdf5_filename, "r")

    X_train = np.array(D["train"])
    X_test = np.array(D["test"])

    # print(f"Loaded dataset: {X_train.shape[0]} samples, {X_train.shape[1]} dimensions")
    return X_train, X_test


X_train, X_test = load_and_transform_dataset(data_path)

seed = 42
np.random.seed(seed)
X_train = X_train[np.random.choice(X_train.shape[0], size, replace=False)]


write_output(X_train, X_test, "deep_100k.hdf5", "angular")