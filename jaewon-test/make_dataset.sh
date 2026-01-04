#!/bin/bash

# 데이터셋별 설정을 배열로 정의
DATA_PATHS=(
    "/home/jaewonoh/workspace/data/deep-image-96-angular.hdf5"
    "/home/jaewonoh/workspace/data/nytimes-256-angular.hdf5"
    "/home/jaewonoh/workspace/data/glove-200-angular.hdf5"
    "/home/jaewonoh/workspace/data/coco-i2i-512-angular.hdf5"
    "/home/jaewonoh/workspace/data/dbpedia-openai-1000k-angular.hdf5"

)

DATA_NAMES=(
    "deep"
    "nyt"
    "glove"
    "coco"
    "dbp"
)


for i in "${!DATA_PATHS[@]}"; do
    DATA_PATH="${DATA_PATHS[$i]}"
    DATA_NAME="${DATA_NAMES[$i]}"

    python3 ~/workspace/ann-benchmark/jaewon-test/sh_make_dataset.py --size 100000 --table_name $DATA_NAME --data_path $DATA_PATH

done
