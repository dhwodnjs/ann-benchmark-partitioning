#!/bin/bash


PG_PORT=8008
PG_USER="ann"
PG_DB="ann"
PG_NAMESPACE=2200
PG_OUT=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out

SOURCE_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnsw.h"
SOURCE_BUILD_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnswbuild.c"
SOURCE_INSERT_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnswinsert.c"

function restart_postgres() {
    $PG_OUT/bin/pg_ctl -D $PG_OUT/pgdb stop -o "-p $PG_PORT"
    sleep 3
    $PG_OUT/bin/pg_ctl -D $PG_OUT/pgdb start -o "-p $PG_PORT"
    sleep 3
}


HEAP_TUPLE=100000
DATA_SIZE="100k"


# 데이터셋별 설정을 배열로 정의
DATA_PATHS=(
    "/home/jaewonoh/workspace/data/deep-image-96-angular.hdf5"
    "/home/jaewonoh/workspace/data/nytimes-256-angular.hdf5"
    "/home/jaewonoh/workspace/data/glove-200-angular.hdf5"
    "/home/jaewonoh/workspace/data/coco-i2i-512-angular.hdf5"
)

#    "/home/jaewonoh/workspace/data/nytimes-256-angular.hdf5"
#    "/home/jaewonoh/workspace/data/glove-200-angular.hdf5"
#    "/home/jaewonoh/workspace/data/coco-i2i-512-angular.hdf5"
#

#BASE_SHARED_BUFFERS_VALUES=(
#    71614464  # deep-image-96-angular
##    127647744  # nytimes-256-angular
##    117039104  # glove-200-angular
##    273047552  # coco-i2i-512-angular
#)


DATA_NAMES=(
    "deep"
    "nyt"
    "glove"
    "coco"
)


BUILD_RATIOS=(100)
POOL_RATIOS=(30)
PARTITION_SIZES=(1 8 16 32 64 128)
BUFFER_RATIOS=(10)


BASE_SHARED_BUFFERS_VALUES=(
    82034688  # deep-image-96-angular
    152887296
    136552448
    273055744
)

#    127647744  # nytimes-256-angular
#    117039104  # glove-200-angular
#    273047552  # coco-i2i-512-angular


LOG_FILE="/home/jaewonoh/workspace/ann-benchmark/jaewon-test/final/1_test_partition_size.log"

for i in "${!DATA_PATHS[@]}"; do
    BASE_SHARED_BUFFERS="${BASE_SHARED_BUFFERS_VALUES[$i]}"
    DATA_PATH="${DATA_PATHS[$i]}"
    DATA_NAME="${DATA_NAMES[$i]}"

    for BUILD_RATIO in "${BUILD_RATIOS[@]}"; do
        BUILD_RATIO_LOG="build_$BUILD_RATIO"

        for PARTITION_SIZE in "${PARTITION_SIZES[@]}"; do
            PARTITION_LOG="partition_$PARTITION_SIZE"

            sed -i "s/#define MAX_NODES_PER_PARTITION [0-9]\+/#define MAX_NODES_PER_PARTITION $PARTITION_SIZE/" $SOURCE_FILE

            for POOL_RATIO in "${POOL_RATIOS[@]}"; do
                POOL_RATIO_LOG="pool_$POOL_RATIO"

                TABLE_NAME="${DATA_NAME}_${DATA_SIZE}_${BUILD_RATIO_LOG}_${PARTITION_LOG}_${POOL_RATIO_LOG}_8kb"
                echo "Search ${TABLE_NAME} ..." >> $LOG_FILE

                for BUFFER_RATIO in "${BUFFER_RATIOS[@]}"; do
                    SHARED_BUFFERS=$(($BASE_SHARED_BUFFERS * $BUFFER_RATIO / 100))

            #        echo "Setting shared_buffers to ${SHARED_BUFFERS}B"
                    sudo sed -i "s/^shared_buffers = .*/shared_buffers = ${SHARED_BUFFERS}B/" $PG_OUT/pgdb/postgresql.conf
                    restart_postgres

                    $PG_OUT/bin/psql -U $PG_USER -p $PG_PORT -d $PG_DB -c "select pg_stat_reset();"
                    SEARCH_RESULTS=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_search.py --table_name $TABLE_NAME --data_path $DATA_PATH --port $PG_PORT)
                    echo "$SEARCH_RESULTS" >> $LOG_FILE

                    HIT_RATIO=$($PG_OUT/bin/psql -p $PG_PORT -U $PG_USER -d $PG_DB -t -c "
                        SELECT relname AS items_embedding_idx, idx_blks_hit, idx_blks_read,
                               ROUND(100.0 * idx_blks_hit / NULLIF(idx_blks_hit + idx_blks_read, 0), 2) AS index_hit_ratio
                        FROM pg_statio_user_indexes
                        WHERE relname = '${TABLE_NAME}'
                        ORDER BY index_hit_ratio DESC;
                    ")

                    echo "Index Hit Ratio for shared_buffers=${SHARED_BUFFERS}B ($BUFFER_RATIO%), Build Ratio=${BUILD_RATIO}%, Pool Ratio=${POOL_RATIO_LOG}:" >> $LOG_FILE
                    echo "$HIT_RATIO" >> $LOG_FILE


                    echo "---------------------------------" >> $LOG_FILE

                done

                echo "" >> $LOG_FILE

            done
        done
    done
done

$PG_OUT/bin/pg_ctl -D $PG_OUT/pgdb stop -o "-p $PG_PORT"
sleep 3

echo "Experiment completed. Results saved in $LOG_FILE."
