#!/bin/bash

#BUFFER_RATIOS=(20 50 60)
#PARTITION_SIZE=64


PG_PORT=8008
PG_USER="ann"
PG_DB="ann"
PG_NAMESPACE=2200
PG_OUT=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out
PG_DIR=$PG_OUT/pgdb_revision

SOURCE_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnsw.h"
SOURCE_BUILD_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnswbuild.c"
SOURCE_INSERT_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnswinsert.c"

function restart_postgres() {
    $PG_OUT/bin/pg_ctl -D $PG_DIR stop -o "-p $PG_PORT"
    sleep 3
    $PG_OUT/bin/pg_ctl -D $PG_DIR start -o "-p $PG_PORT"
    sleep 3
}
#-l $LOG_FILE_COUNT

#
HEAP_TUPLE=20000
DATA_SIZE="20k"


#
HEAP_TUPLE=100000
DATA_SIZE="100k"


#HEAP_TUPLE=9990000
#DATA_SIZE="10m"

#
#HEAP_TUPLE=3000000
#DATA_SIZE="30m"
#
#
#HEAP_TUPLE=1000000
#DATA_SIZE="1m"

#HEAP_TUPLE=100000
#DATA_SIZE="100k"
#
##
#HEAP_TUPLE=5000000
#DATA_SIZE="5m"




# 데이터셋별 설정을 배열로 정의
DATA_PATHS=(
    "/home/jaewonoh/workspace/data/deep-image-96-angular.hdf5"
#    "/home/jaewonoh/workspace/data/openai-1536-5m.hdf5"
#    "/home/jaewonoh/workspace/data/glove-200-angular.hdf5"
)
#"/home/jaewonoh/workspace/data/sift-128-euclidean.hdf5"
#    "/home/jaewonoh/workspace/data/deep-image-96-angular.hdf5"
#    "/home/jaewonoh/workspace/data/nytimes-256-angular.hdf5"
#    "/home/jaewonoh/workspace/data/glove-200-angular.hdf5"
#    "/home/jaewonoh/workspace/data/coco-i2i-512-angular.hdf5"
#    "/home/jaewonoh/workspace/data/nytimes-256-angular.hdf5"
#    "/home/jaewonoh/workspace/data/glove-200-angular.hdf5"


#BASE_SHARED_BUFFERS_VALUES=(
#    71614464  # deep-image-96-angular
##    127647744  # nytimes-256-angular
##    117039104  # glove-200-angular
##    273047552  # coco-i2i-512-angular
#)


DATA_NAMES=(
    "deep"
#    "c4"
#    "glove"
)

#
#    "nyt"
#    "glove"
#    "coco"

#    "sift"
#    "nyt"
#    "glove"



BUILD_RATIOS=(100)
POOL_RATIOS=(30)
PARTITION_SIZES=(64)


LOG_FILE="/home/jaewonoh/workspace/ann-benchmark/jaewon-test/final/0_build_summer.log"

for i in "${!DATA_PATHS[@]}"; do
    DATA_PATH="${DATA_PATHS[$i]}"
    DATA_NAME="${DATA_NAMES[$i]}"

    for BUILD_RATIO in "${BUILD_RATIOS[@]}"; do
        BUILD_RATIO_LOG="build_$BUILD_RATIO"

        for PARTITION_SIZE in "${PARTITION_SIZES[@]}"; do
            PARTITION_LOG="prt_$PARTITION_SIZE"

            LOG_FILE_COUNT="/home/jaewonoh/workspace/ann-benchmark/jaewon-test/final/16_log_in_neighbor_${DATA_NAME}_${DATA_SIZE}_${PARTITION_LOG}.log"

            sed -i "s/#define MAX_NODES_PER_PARTITION [0-9]\+/#define MAX_NODES_PER_PARTITION $PARTITION_SIZE/" $SOURCE_FILE

            for POOL_RATIO in "${POOL_RATIOS[@]}"; do
                POOL_RATIO_LOG="pool_$POOL_RATIO"

                TABLE_NAME="${DATA_NAME}_${DATA_SIZE}_${BUILD_RATIO_LOG}_${PARTITION_LOG}_${POOL_RATIO_LOG}_stv1" ## v: vanilla, p: partitioning, s: shuffle, i: initial, t: test

                echo "Build ${TABLE_NAME} ..." >> $LOG_FILE

                POOL_SIZE=$(awk "BEGIN {print $POOL_RATIO / 100}")
                sed -i "s/#define INSERT_PAGE_PER_PARTITION [0-9]\+\(\.[0-9]\+\)\?/#define INSERT_PAGE_PER_PARTITION $POOL_SIZE/" $SOURCE_FILE

                cd /home/jaewonoh/workspace/git/pgpgpg/pgvector
                make PG_CONFIG=/home/jaewonoh/mnt/samsung-nvme/jaewonoh/workspace/pg_out/bin/pg_config clean;
                make PG_CONFIG=/home/jaewonoh/mnt/samsung-nvme/jaewonoh/workspace/pg_out/bin/pg_config -j 32;
                make install PG_CONFIG=/home/jaewonoh/mnt/samsung-nvme/jaewonoh/workspace/pg_out/bin/pg_config;

                restart_postgres

                BUILD_TIME=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_build.py --size $HEAP_TUPLE --ratio $BUILD_RATIO --table_name $TABLE_NAME --data_path $DATA_PATH --port $PG_PORT)

                echo "Build Time: $BUILD_TIME" >> $LOG_FILE

                INDEX_STATS=$($PG_OUT/bin/psql -p $PG_PORT -U $PG_USER -d $PG_DB -t -c "
                    SELECT oid, pg_table_size(oid), relname, relnamespace, reltype, relowner,
                           relfilenode, reltablespace, relpages, reltuples, reltoastrelid, relhasindex
                    FROM pg_class
                    WHERE relnamespace = $PG_NAMESPACE
                    AND (relname = '$TABLE_NAME' OR relname = '${TABLE_NAME}_embedding_idx');
                ")

                echo "$INDEX_STATS" >> $LOG_FILE

                echo "" >> $LOG_FILE

            done
        done
    done
done

$PG_OUT/bin/pg_ctl -D $PG_DIR stop -o "-p $PG_PORT"
sleep 3

echo "Experiment completed. Results saved in $LOG_FILE."