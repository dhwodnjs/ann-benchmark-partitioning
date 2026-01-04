#!/bin/bash

#BUFFER_RATIOS=(20 50 60)
#PARTITION_SIZE=64


PG_PORT=8008
PG_USER="ann"
PG_DB="ann"
PG_NAMESPACE=2200


PG_OUT_8=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out
PG_OUT_16=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out_16
PG_OUT_32=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out_32
PG_OUT_IO_32=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out_io_32


SOURCE_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnsw.h"
SOURCE_BUILD_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnswbuild.c"
SOURCE_INSERT_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnswinsert.c"


function restart_postgres() {
    $PG_OUT/bin/pg_ctl -D $PG_OUT/pgdb stop -o "-p $PG_PORT"
    sleep 3

    while $PG_OUT/bin/pg_ctl -D $PG_OUT/pgdb status > /dev/null 2>&1; do
        echo "Waiting for PostgreSQL to stop..."
        sleep 1
    done

    $PG_OUT/bin/pg_ctl -D $PG_OUT/pgdb start -o "-p $PG_PORT"
    sleep 3
}

HEAP_TUPLE=100000
DATA_SIZE="100k"

DATA_PATHS=(
    "/home/jaewonoh/workspace/data/dbpedia-openai-1000k-angular.hdf5"
)

#    "/home/jaewonoh/workspace/data/nytimes-256-angular.hdf5"
#    "/home/jaewonoh/workspace/data/glove-200-angular.hdf5"
#    "/home/jaewonoh/workspace/data/coco-i2i-512-angular.hdf5"
#

DATA_NAMES=(
    "dbp"
)

BUILD_RATIOS=(100)
POOL_RATIOS=(30)
PARTITION_SIZES=(64)


# PG_OUT 경로를 배열로 저장
PG_OUT_DIRS=(
    "$PG_OUT_IO_32"
)
  #    "$PG_OUT_32"

PG_OUT_SIZE=("io_32")



LOG_FILE="/home/jaewonoh/workspace/ann-benchmark/jaewon-test/final/0_build.log"


for i in "${!PG_OUT_DIRS[@]}"; do

    PG_OUT="${PG_OUT_DIRS[$i]}";
    PG_SIZE="${PG_OUT_SIZE[$i]}";

#    PAGE_LOG="page_$PG_SIZE"


    for i in "${!DATA_PATHS[@]}"; do
        DATA_PATH="${DATA_PATHS[$i]}"
        DATA_NAME="${DATA_NAMES[$i]}"

        for BUILD_RATIO in "${BUILD_RATIOS[@]}"; do
            BUILD_RATIO_LOG="build_$BUILD_RATIO"

            for PARTITION_SIZE in "${PARTITION_SIZES[@]}"; do
                PARTITION_LOG="prt_$PARTITION_SIZE"

                sed -i "s/#define MAX_NODES_PER_PARTITION [0-9]\+/#define MAX_NODES_PER_PARTITION $PARTITION_SIZE/" $SOURCE_FILE

                for POOL_RATIO in "${POOL_RATIOS[@]}"; do
                    POOL_RATIO_LOG="pool_$POOL_RATIO"

                    TABLE_NAME="${DATA_NAME}_${DATA_SIZE}_${BUILD_RATIO_LOG}_${PARTITION_LOG}_${POOL_RATIO_LOG}_${PG_SIZE}kb_v"

                    echo "Build ${TABLE_NAME} ..." >> $LOG_FILE

                    POOL_SIZE=$(awk "BEGIN {print $POOL_RATIO / 100}")
                    sed -i "s/#define INSERT_PAGE_PER_PARTITION [0-9]\+\(\.[0-9]\+\)\?/#define INSERT_PAGE_PER_PARTITION $POOL_SIZE/" $SOURCE_FILE
#
#                    cd /home/jaewonoh/workspace/git/pgpgpg/postgres
#                    make clean;
#                    make -j 32;
#                    make install;
#
                    cd /home/jaewonoh/workspace/git/pgpgpg/pgvector
                    make PG_CONFIG=$PG_OUT/bin/pg_config clean;
                    make PG_CONFIG=$PG_OUT/bin/pg_config -j 32;
                    make install PG_CONFIG=$PG_OUT/bin/pg_config;

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
done

$PG_OUT/bin/pg_ctl -D $PG_OUT/pgdb stop -o "-p $PG_PORT"
sleep 3

echo "Experiment completed. Results saved in $LOG_FILE."