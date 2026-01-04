#!/bin/bash


PG_PORT=8008
PG_USER="ann"
PG_DB="ann"
PG_NAMESPACE=2200


PG_OUT_4=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out_4
PG_OUT_8=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out
PG_OUT_16=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out_16
PG_OUT_32=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out_32


SOURCE_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnsw.h"
SOURCE_BUILD_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnswbuild.c"
SOURCE_INSERT_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnswinsert.c"


HEAP_TUPLE=100000
DATA_SIZE="100k"

DATA_PATHS=(
#    "/home/jaewonoh/workspace/data/deep-image-96-angular.hdf5"
    "/home/jaewonoh/workspace/data/openai-1536-5m.hdf5"
)
DATA_NAMES=(
#    "deep"
    "c4"
)

BUILD_RATIOS=(100)
POOL_RATIOS=(30)
PARTITION_SIZES=(64)
BUFFER_RATIOS=(10)



BASE_SHARED_BUFFERS_VALUES=(
    819208192
)

#    152895488
#    136552448
#    273055744
#    819208192



PG_OUT_DIRS=(
#    "$PG_OUT_4"
    "$PG_OUT_8"
    "$PG_OUT_16"
    "$PG_OUT_32"
)
PG_OUT_SIZE=(8 16 32)


LOG_FILE="/home/jaewonoh/workspace/ann-benchmark/jaewon-test/final/15_search_revision.log"



for i in "${!PG_OUT_DIRS[@]}"; do

    PG_OUT="${PG_OUT_DIRS[$i]}";
    PG_SIZE="${PG_OUT_SIZE[$i]}";


    if [ "$PG_SIZE" -eq 8 ]; then
        PG_DB_DIR="$PG_OUT/pgdb_revision"
    else
        PG_DB_DIR="$PG_OUT/pgdb"
    fi


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


#        LOG_FILE_COUNT="/home/jaewonoh/workspace/ann-benchmark/jaewon-test/final/5_visit_node_${DATA_NAME}_${PG_SIZE}kb.log"


        for BUILD_RATIO in "${BUILD_RATIOS[@]}"; do
            BUILD_RATIO_LOG="build_$BUILD_RATIO"

            for PARTITION_SIZE in "${PARTITION_SIZES[@]}"; do
                PARTITION_LOG="prt_$PARTITION_SIZE" ## prt / partition 이름 주의

                for POOL_RATIO in "${POOL_RATIOS[@]}"; do
                    POOL_RATIO_LOG="pool_$POOL_RATIO"

#                    TABLE_NAME="${DATA_NAME}_${DATA_SIZE}_${BUILD_RATIO_LOG}_${PARTITION_LOG}_${POOL_RATIO_LOG}_${PG_SIZE}kb"
                    TABLE_NAME="${DATA_NAME}_${DATA_SIZE}_${BUILD_RATIO_LOG}_${PARTITION_LOG}_${POOL_RATIO_LOG}_${PG_SIZE}kb_t"

                    echo "Search ${TABLE_NAME} ..." >> $LOG_FILE

                    for BUFFER_RATIO in "${BUFFER_RATIOS[@]}"; do
                        SHARED_BUFFERS=$(($BASE_SHARED_BUFFERS * $BUFFER_RATIO / 100))

                #        echo "Setting shared_buffers to ${SHARED_BUFFERS}B"
                        sudo sed -i "s/^shared_buffers = .*/shared_buffers = ${SHARED_BUFFERS}B/" $PG_DB_DIR/postgresql.conf

                        # Stop PostgreSQL after loop ends
                        $PG_OUT/bin/pg_ctl -D "$PG_DB_DIR" stop -o "-p $PG_PORT"
                        sleep 3

                        # Start PostgreSQL once per PG_OUT
                        $PG_OUT/bin/pg_ctl -D "$PG_DB_DIR" start -o "-p $PG_PORT"
                        sleep 3

                        $PG_OUT/bin/psql -U $PG_USER -p $PG_PORT -d $PG_DB -c "select pg_stat_reset();"
                        SEARCH_RESULTS=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_search.py --table_name $TABLE_NAME --data_path $DATA_PATH --port $PG_PORT --num 0)
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


    # Stop PostgreSQL after loop ends
    $PG_OUT/bin/pg_ctl -D "$PG_DB_DIR" stop -o "-p $PG_PORT"
    sleep 3
done


echo "Experiment completed. Results saved in $LOG_FILE."
