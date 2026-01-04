#!/bin/bash


PG_PORT=8008
PG_USER="ann"
PG_DB="ann"
PG_NAMESPACE=2200


PG_OUT_8=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out
PG_OUT_16=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out_16
PG_OUT_32=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out_32
PG_OUT_IO_32=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out_io_32
PG_OUT_FINAL=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out_final
PG_OUT_FINAL_IO=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out_final_io


SOURCE_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnsw.h"
SOURCE_BUILD_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnswbuild.c"
SOURCE_INSERT_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnswinsert.c"


function restart_postgres() {
    $PG_OUT/bin/pg_ctl -D $PG_DB_INDEX stop -o "-p $PG_PORT"
    sleep 3

    while $PG_OUT/bin/pg_ctl -D $PG_DB_INDEX status > /dev/null 2>&1; do
        echo "Waiting for PostgreSQL to stop..."
        sleep 1
    done

    $PG_OUT/bin/pg_ctl -D $PG_DB_INDEX start -o "-p $PG_PORT"
    sleep 3
}
# -l $LOG_FILE_COUNT

HEAP_TUPLE=100000
DATA_SIZE="100k"

#
#HEAP_TUPLE=1000000
#DATA_SIZE="1m"

#HEAP_TUPLE=9990000
#DATA_SIZE="10m"

# 데이터셋별 설정을 배열로 정의
DATA_PATHS=(
#    "/home/jaewonoh/workspace/data/deep-image-96-angular.hdf5"
    "/home/jaewonoh/workspace/data/openai-1536-5m.hdf5"
)

#"/home/jaewonoh/workspace/data/deep-image-96-angular.hdf5"
#    "/home/jaewonoh/workspace/data/nytimes-256-angular.hdf5"
#    "/home/jaewonoh/workspace/data/glove-200-angular.hdf5"
#    "/home/jaewonoh/workspace/data/coco-i2i-512-angular.hdf5"
#


DATA_NAMES=(
#    "deep"
    "dbp"
)
#
#BUILD_RATIOS=(100)
#POOL_RATIOS=(30)
#PARTITION_SIZES=(64)


BUILD_RATIOS=(90)
POOL_RATIOS=(30)
PARTITION_SIZES=(64)

# (5, 64) 추가 실험 + vanilla pgdb 바꿔서 실험

#BUFFER_RATIOS=(20)

BUFFER_RATIO=20


BASE_SHARED_BUFFERS_VALUES=(
    82034688
)

#82034688
#152887296
#136552448
#273055744
#819208192


# PG_OUT 경로를 배열로 저장
PG_OUT_DIRS=(
    "$PG_OUT_FINAL_IO"
)
  #    "$PG_OUT_32"

PG_OUT_SIZE=(8)


LOG_FILE="/home/jaewonoh/workspace/ann-benchmark/jaewon-test/final/0_insert.log"



for i in "${!PG_OUT_DIRS[@]}"; do

    PG_OUT="${PG_OUT_DIRS[$i]}";
    PG_SIZE="${PG_OUT_SIZE[$i]}";
    PG_DB_INDEX="${PG_OUT}/pgdb_0707"

#
#    cd /home/jaewonoh/workspace/git/pgpgpg/postgres
#    make PG_CONFIG=$PG_OUT/bin/pg_config clean;
#    make PG_CONFIG=$PG_OUT/bin/pg_config -j 32;
#    make PG_CONFIG=$PG_OUT/bin/pg_config install ;
#
#
    cd /home/jaewonoh/workspace/git/pgpgpg/pgvector
    make PG_CONFIG=$PG_OUT/bin/pg_config clean;
    make PG_CONFIG=$PG_OUT/bin/pg_config -j 32;
    make install PG_CONFIG=$PG_OUT/bin/pg_config;

    for i in "${!DATA_PATHS[@]}"; do
        BASE_SHARED_BUFFERS="${BASE_SHARED_BUFFERS_VALUES[$i]}"
        DATA_PATH="${DATA_PATHS[$i]}"
        DATA_NAME="${DATA_NAMES[$i]}"

        for BUILD_RATIO in "${BUILD_RATIOS[@]}"; do
            BUILD_RATIO_LOG="build_$BUILD_RATIO"

            for PARTITION_SIZE in "${PARTITION_SIZES[@]}"; do
                PARTITION_LOG="prt_$PARTITION_SIZE" ## prt / partition 이름 주의

                sed -i "s/#define MAX_NODES_PER_PARTITION [0-9]\+/#define MAX_NODES_PER_PARTITION $PARTITION_SIZE/" $SOURCE_FILE

                for POOL_RATIO in "${POOL_RATIOS[@]}"; do
                    POOL_RATIO_LOG="pool_$POOL_RATIO"

                    TABLE_NAME="${DATA_NAME}_${DATA_SIZE}_${BUILD_RATIO_LOG}_${PARTITION_LOG}_${POOL_RATIO_LOG}_t3"
                    LOG_FILE_COUNT="/home/jaewonoh/workspace/ann-benchmark/jaewon-test/final/19_insert_io_${DATA_NAME}_${DATA_SIZE}_${PARTITION_LOG}_t3.log"

                    POOL_SIZE=$(awk "BEGIN {print $POOL_RATIO / 100}")
                    sed -i "s/#define INSERT_PAGE_PER_PARTITION [0-9]\+\(\.[0-9]\+\)\?/#define INSERT_PAGE_PER_PARTITION $POOL_SIZE/" $SOURCE_FILE

                    cd /home/jaewonoh/workspace/git/pgpgpg/pgvector
                    make PG_CONFIG=$PG_OUT/bin/pg_config clean;
                    make PG_CONFIG=$PG_OUT/bin/pg_config -j 32;
                    make install PG_CONFIG=$PG_OUT/bin/pg_config;


                    SHARED_BUFFERS=$(($BASE_SHARED_BUFFERS * $BUFFER_RATIO / 100))
                    sudo sed -i "s/^shared_buffers = .*/shared_buffers = ${SHARED_BUFFERS}B/" $PG_DB_INDEX/postgresql.conf

                    restart_postgres

                    echo "Insert ${TABLE_NAME} ..." >> $LOG_FILE
                    INSERT_TIME=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_insert.py --size $HEAP_TUPLE --ratio $BUILD_RATIO --table_name $TABLE_NAME --data_path $DATA_PATH --port $PG_PORT)

                    echo "Insert Time: $INSERT_TIME" >> $LOG_FILE

                    INDEX_STATS=$($PG_OUT/bin/psql -p $PG_PORT -U $PG_USER -d $PG_DB -t -c "
                        SELECT oid, pg_table_size(oid), relname, relnamespace, reltype, relowner,
                               relfilenode, reltablespace, relpages, reltuples, reltoastrelid, relhasindex
                        FROM pg_class
                        WHERE relnamespace = $PG_NAMESPACE
                        AND (relname = '$TABLE_NAME' OR relname = '${TABLE_NAME}_embedding_idx');
                    ")

                    echo "$INDEX_STATS" >> $LOG_FILE

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
                    echo "" >> $LOG_FILE

                done
            done
        done
    done
done


$PG_OUT/bin/pg_ctl -D $PG_DB_INDEX stop -o "-p $PG_PORT"
sleep 3

echo "Experiment completed. Results saved in $LOG_FILE."
