#!/bin/bash



BUILD_RATIOS=(80 60 50)
BUFFER_RATIOS=(10 20 30 40 50)
POOL_RATIOS=(30)
#PARTITION_SIZES=(64)
PG_PORT=8008

PG_USER="ann"
PG_DB="ann"
PG_NAMESPACE=2200
PG_OUT=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out

HEAP_TUPLE=100000
PARTITION_SIZE=64

TABLE_NAME="items"

#
#DATA_PATH="/home/jaewonoh/workspace/data/deep-image-96-angular.hdf5"
##DATA_PATH="/home/jaewonoh/workspace/data/nytimes-256-angular.hdf5"
##DATA_PATH="/home/jaewonoh/workspace/data/glove-200-angular.hdf5"
##DATA_PATH="/home/jaewonoh/workspace/data/coco-i2i-512-angular.hdf5"
#BASE_SHARED_BUFFERS=71524352
#LOG_NAME="deep-image-96-angular"


SOURCE_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnsw.h"
SOURCE_BUILD_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnswbuild.c"
SOURCE_INSERT_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnswbuild.c"


function restart_postgres() {
    $PG_OUT/bin/pg_ctl -D $PG_OUT/pgdb stop -o "-p $PG_PORT"
    sleep 3
    $PG_OUT/bin/pg_ctl -D $PG_OUT/pgdb start -o "-p $PG_PORT"
    sleep 3
}

# 데이터셋별 설정을 배열로 정의
DATA_PATHS=(
    "/home/jaewonoh/workspace/data/deep-image-96-angular.hdf5"
)

#    "/home/jaewonoh/workspace/data/nytimes-256-angular.hdf5"
#    "/home/jaewonoh/workspace/data/glove-200-angular.hdf5"
#    "/home/jaewonoh/workspace/data/coco-i2i-512-angular.hdf5"

BASE_SHARED_BUFFERS_VALUES=(
    71524352  # deep-image-96-angular
    127647744  # nytimes-256-angular
    117039104  # glove-200-angular
    273047552  # coco-i2i-512-angular
)

LOG_NAMES=(
    "deep-image-96-angular"
)

#
#    "nytimes-256-angular"
#    "glove-200-angular"
#    "coco-i2i-512-angular"



for i in "${!DATA_PATHS[@]}"; do
    DATA_PATH="${DATA_PATHS[$i]}"
#    BASE_SHARED_BUFFERS="${BASE_SHARED_BUFFERS_VALUES[$i]}"
    LOG_NAME="${LOG_NAMES[$i]}"


    echo "Running experiments for dataset: $LOG_NAME"
    echo "Data Path: $DATA_PATH"
#    echo "Base Shared Buffers: $BASE_SHARED_BUFFERS"


    for BUILD_RATIO in "${BUILD_RATIOS[@]}"; do

        BUILD_RATIO_LOG="build_$BUILD_RATIO"

#        for POOL_RATIO in "${POOL_RATIOS[@]}"; do
#
#
#            POOL_RATIO_LOG="pool_$POOL_RATIO"
#
#            LOG_FILE="/home/jaewonoh/workspace/ann-benchmark/jaewon-test/insert/${LOG_NAME}_${BUILD_RATIO_LOG}_${POOL_RATIO_LOG}.log"
#
#
#            if [ -f "$LOG_FILE" ]; then
#                echo "Skipping experiment: Log file already exists -> $LOG_FILE"
#                continue
#            fi
#
#
#            echo "Starting experiment with Build Ratio=${BUILD_RATIO}%, Pool Ratio=${POOL_RATIO_LOG} ..." > $LOG_FILE
#
#
#
#    #        POOL_SIZE=$(($HEAP_TUPLE * $BUILD_RATIO / 100 / $PARTITION_SIZE * $POOL_RATIO / 100))
#            POOL_SIZE=$(( ($HEAP_TUPLE * $BUILD_RATIO * $POOL_RATIO) / (100 * $PARTITION_SIZE * 100) ))
#
#
#            echo "Modifying source code to set max_insert_pool_size = $POOL_SIZE"
#            sed -i "s/#define MAX_INSERT_POOL_SIZE [0-9]\+/#define MAX_INSERT_POOL_SIZE $POOL_SIZE/" $SOURCE_FILE
#
#            cd /home/jaewonoh/workspace/git/pgpgpg/pgvector
#
#            make PG_CONFIG=/home/jaewonoh/mnt/samsung-nvme/jaewonoh/workspace/pg_out/bin/pg_config clean;
#            make PG_CONFIG=/home/jaewonoh/mnt/samsung-nvme/jaewonoh/workspace/pg_out/bin/pg_config -j 32;
#            make install PG_CONFIG=/home/jaewonoh/mnt/samsung-nvme/jaewonoh/workspace/pg_out/bin/pg_config;
#
#            restart_postgres
#
#            echo "Running build.py with data ratio $BUILD_RATIO%..."
#            BUILD_TIME=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_build.py --size $HEAP_TUPLE --ratio $BUILD_RATIO --table_name $TABLE_NAME --data_path $DATA_PATH)
#
#
#            echo "Running insert.py with pool ratio $POOL_RATIO%..."
#            INSERT_TIME=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_insert.py --size $HEAP_TUPLE --ratio $BUILD_RATIO --table_name $TABLE_NAME --data_path $DATA_PATH)
#
#            echo "Running ANALYZE..."
#            $PG_OUT/bin/psql -p 8000 -U $PG_USER -d $PG_DB -c "ANALYZE;"
#
#            echo "Fetching index and page statistics..."
#            INDEX_STATS=$($PG_OUT/bin/psql -p 8000 -U $PG_USER -d $PG_DB -t -c "
#                SELECT oid, pg_table_size(oid), relname, relnamespace, reltype, relowner,
#                       relfilenode, reltablespace, relpages, reltuples, reltoastrelid, relhasindex
#                FROM pg_class
#                WHERE relnamespace = $PG_NAMESPACE;
#            ")
#
#            echo "Index Stats for Build Ratio=${BUILD_RATIO}%, Pool Ratio=${POOL_RATIO_LOG}:" >> $LOG_FILE
#            echo "$INDEX_STATS" >> $LOG_FILE
#            echo "Build Time: $BUILD_TIME, Insert Time: $INSERT_TIME" >> $LOG_FILE
#
#
#            for BUFFER_RATIO in "${BUFFER_RATIOS[@]}"; do
#
#                SHARED_BUFFERS=$(($BASE_SHARED_BUFFERS * $BUFFER_RATIO / 100))
#
#
#                echo "Testing with shared_buffers = ${SHARED_BUFFERS}B ($BUFFER_RATIO%), Build Ratio=${BUILD_RATIO}%, Pool Ratio=${POOL_RATIO_LOG}" >> $LOG_FILE
#
#
#        #        echo "Setting shared_buffers to ${SHARED_BUFFERS}B"
#                sudo sed -i "s/^shared_buffers = .*/shared_buffers = ${SHARED_BUFFERS}B/" $PG_OUT/pgdb/postgresql.conf
#                restart_postgres
#
#                $PG_OUT/bin/psql -U $PG_USER -p 8000 -d $PG_DB -c "select pg_stat_reset();"
#
#        #        echo "Running search.py..."
#                SEARCH_RESULTS=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_search.py --table_name $TABLE_NAME --data_path $DATA_PATH)
#
#                echo "$SEARCH_RESULTS" >> $LOG_FILE
#
#
#        #        echo "Fetching Index Hit Ratio..."
#                HIT_RATIO=$($PG_OUT/bin/psql -p 8000 -U $PG_USER -d $PG_DB -t -c "
#                    SELECT relname AS items_embedding_idx, idx_blks_hit, idx_blks_read,
#                           ROUND(100.0 * idx_blks_hit / NULLIF(idx_blks_hit + idx_blks_read, 0), 2) AS index_hit_ratio
#                    FROM pg_statio_user_indexes
#                    ORDER BY index_hit_ratio DESC;
#                ")
#
#                echo "Index Hit Ratio for shared_buffers=${SHARED_BUFFERS}B ($BUFFER_RATIO%), Build Ratio=${BUILD_RATIO}%, Pool Ratio=${POOL_RATIO_LOG}:" >> $LOG_FILE
#                echo "$HIT_RATIO" >> $LOG_FILE
#
#
#                echo "---------------------------------" >> $LOG_FILE
#            done
#        done

        for POOL_RATIO in "${POOL_RATIOS[@]}"; do


#            POOL_RATIO_LOG="pool_static_$POOL_RATIO"
            POOL_RATIO_LOG="pool_vanilla"

            LOG_FILE="/home/jaewonoh/workspace/ann-benchmark/jaewon-test/insert/${LOG_NAME}_${BUILD_RATIO_LOG}_${POOL_RATIO_LOG}_direct.log"


            if [ -f "$LOG_FILE" ]; then
                echo "Skipping experiment: Log file already exists -> $LOG_FILE"
                continue
            fi

            echo "Starting experiment with Build Ratio=${BUILD_RATIO}%, Pool Ratio=${POOL_RATIO_LOG} ..." > $LOG_FILE
#
    #        POOL_SIZE=$(($HEAP_TUPLE / $PARTITION_SIZE * $POOL_RATIO / 100))
            POOL_SIZE=$(( ($HEAP_TUPLE * $POOL_RATIO) / ($PARTITION_SIZE * 100) ))


            echo "Modifying source code to set max_insert_pool_size = $POOL_SIZE"
            sed -i "s/#define MAX_INSERT_POOL_SIZE [0-9]\+/#define MAX_INSERT_POOL_SIZE $POOL_SIZE/" $SOURCE_FILE

            cd /home/jaewonoh/workspace/git/pgpgpg/pgvector

            make PG_CONFIG=/home/jaewonoh/mnt/samsung-nvme/jaewonoh/workspace/pg_out/bin/pg_config clean;
            make PG_CONFIG=/home/jaewonoh/mnt/samsung-nvme/jaewonoh/workspace/pg_out/bin/pg_config -j 32;
            make install PG_CONFIG=/home/jaewonoh/mnt/samsung-nvme/jaewonoh/workspace/pg_out/bin/pg_config;

            restart_postgres

            echo "Running build.py with data ratio $BUILD_RATIO%..."
            BUILD_TIME=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_build.py --size $HEAP_TUPLE --ratio $BUILD_RATIO --table_name $TABLE_NAME --data_path $DATA_PATH --port $PG_PORT)

            echo "Running insert.py with pool ratio $POOL_RATIO%..."
            INSERT_TIME=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_insert.py --size $HEAP_TUPLE --ratio $BUILD_RATIO --table_name $TABLE_NAME --data_path $DATA_PATH --port $PG_PORT)

            echo "Running ANALYZE..."
            $PG_OUT/bin/psql -p $PG_PORT -U $PG_USER -d $PG_DB -c "ANALYZE;"

            echo "Fetching index and page statistics..."
            INDEX_STATS=$($PG_OUT/bin/psql -p $PG_PORT -U $PG_USER -d $PG_DB -t -c "
                SELECT oid, pg_table_size(oid), relname, relnamespace, reltype, relowner,
                       relfilenode, reltablespace, relpages, reltuples, reltoastrelid, relhasindex
                FROM pg_class
                WHERE relnamespace = $PG_NAMESPACE;
            ")

            echo "Index Stats for Build Ratio=${BUILD_RATIO}%, Pool Ratio=${POOL_RATIO_LOG}:" >> $LOG_FILE
            echo "$INDEX_STATS" >> $LOG_FILE


            INDEX_SIZE=$($PG_OUT/bin/psql -p $PG_PORT -U $PG_USER -d $PG_DB -t -c "SELECT pg_relation_size('items_embedding_idx');")
            BASE_SHARED_BUFFERS=$(echo $INDEX_SIZE | tr -d ' ')



            echo "Build Time: $BUILD_TIME, Insert Time: $INSERT_TIME" >> $LOG_FILE


#            for BUFFER_RATIO in "${BUFFER_RATIOS[@]}"; do
#
#                SHARED_BUFFERS=$(($BASE_SHARED_BUFFERS * $BUFFER_RATIO / 100))
#
#
#                echo "Testing with shared_buffers = ${SHARED_BUFFERS}B ($BUFFER_RATIO%), Build Ratio=${BUILD_RATIO}%, Pool Ratio=${POOL_RATIO_LOG}}" >> $LOG_FILE
#
#
#        #        echo "Setting shared_buffers to ${SHARED_BUFFERS}B"
#                sudo sed -i "s/^shared_buffers = .*/shared_buffers = ${SHARED_BUFFERS}B/" $PG_OUT/pgdb/postgresql.conf
#                restart_postgres
#
#
#                $PG_OUT/bin/psql -U $PG_USER -p $PG_PORT -d $PG_DB -c "select pg_stat_reset();"
#
#        #        echo "Running search.py..."
#                SEARCH_RESULTS=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_search.py --table_name $TABLE_NAME --data_path $DATA_PATH --port $PG_PORT)
#
#                echo "$SEARCH_RESULTS" >> $LOG_FILE
#
#
#        #        echo "Fetching Index Hit Ratio..."
#                HIT_RATIO=$($PG_OUT/bin/psql -p $PG_PORT -U $PG_USER -d $PG_DB -t -c "
#                    SELECT relname AS items_embedding_idx, idx_blks_hit, idx_blks_read,
#                           ROUND(100.0 * idx_blks_hit / NULLIF(idx_blks_hit + idx_blks_read, 0), 2) AS index_hit_ratio
#                    FROM pg_statio_user_indexes
#                    ORDER BY index_hit_ratio DESC;
#                ")
#
#                echo "Index Hit Ratio for shared_buffers=${SHARED_BUFFERS}B ($BUFFER_RATIO%), Build Ratio=${BUILD_RATIO}%, Pool Ratio=${POOL_RATIO_LOG}:" >> $LOG_FILE
#                echo "$HIT_RATIO" >> $LOG_FILE
#
#
#                echo "---------------------------------" >> $LOG_FILE
#            done
        done


#
#        echo "Running build.py with data ratio $BUILD_RATIO%..."
#        BUILD_TIME=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_build.py --size $HEAP_TUPLE --ratio $BUILD_RATIO --table_name $TABLE_NAME --data_path $DATA_PATH)
#
#
#        POOL_RATIO_LOG="pool_vanilla"
#
#        LOG_FILE="/home/jaewonoh/workspace/ann-benchmark/jaewon-test/insert/${LOG_NAME}_${BUILD_RATIO_LOG}_${POOL_RATIO_LOG}.log"
#
#        echo "Modifying source code to set vanilla insert"
#
#        sed -i 's|^\(\s*\)//\s*\(HnswInsertTupleOnDisk(index, &support, value, heaptid, false);\)|\2|; s|^\(\s*\)\(HnswInsertTupleOnDiskWithPartition(index, &support, value, heaptid, false);\)|\1// \2|' $SOURCE_INSERT_FILE
#
#        cd /home/jaewonoh/workspace/git/pgpgpg/pgvector
#
#        make install PG_CONFIG=/home/jaewonoh/mnt/samsung-nvme/jaewonoh/workspace/pg_out/bin/pg_config;
#
#        restart_postgres
#
#        echo "Running insert.py with pool ratio $POOL_RATIO%..."
#        INSERT_TIME=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_insert.py --size $HEAP_TUPLE --ratio $BUILD_RATIO --table_name $TABLE_NAME --data_path $DATA_PATH)
#
#        echo "Running ANALYZE..."
#        $PG_OUT/bin/psql -p 8000 -U $PG_USER -d $PG_DB -c "ANALYZE;"
#
#        echo "Fetching index and page statistics..."
#        INDEX_STATS=$($PG_OUT/bin/psql -p 8000 -U $PG_USER -d $PG_DB -t -c "
#            SELECT oid, pg_table_size(oid), relname, relnamespace, reltype, relowner,
#                   relfilenode, reltablespace, relpages, reltuples, reltoastrelid, relhasindex
#            FROM pg_class
#            WHERE relnamespace = $PG_NAMESPACE;
#        ")
#
#
#        echo "Index Stats for Build Ratio=${BUILD_RATIO}%, Pool Ratio=${POOL_RATIO_LOG}:" >> $LOG_FILE
#        echo "$INDEX_STATS" >> $LOG_FILE
#
#
#        echo "Build Time: $BUILD_TIME, Insert Time: $INSERT_TIME" >> $LOG_FILE
#
#
#        for BUFFER_RATIO in "${BUFFER_RATIOS[@]}"; do
#
#            SHARED_BUFFERS=$(($BASE_SHARED_BUFFERS * $BUFFER_RATIO / 100))
#
#
#            echo "Testing with shared_buffers = ${SHARED_BUFFERS}B ($BUFFER_RATIO%), Build Ratio=${BUILD_RATIO}%, Pool Ratio=${POOL_RATIO_LOG}" >> $LOG_FILE
#
#
#    #        echo "Setting shared_buffers to ${SHARED_BUFFERS}B"
#            sudo sed -i "s/^shared_buffers = .*/shared_buffers = ${SHARED_BUFFERS}B/" $PG_OUT/pgdb/postgresql.conf
#            restart_postgres
#
#
#            $PG_OUT/bin/psql -U $PG_USER -p 8000 -d $PG_DB -c "select pg_stat_reset();"
#
#    #        echo "Running search.py..."
#            SEARCH_RESULTS=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_search.py --table_name $TABLE_NAME --data_path $DATA_PATH)
#
#            echo "$SEARCH_RESULTS" >> $LOG_FILE
#
#
#    #        echo "Fetching Index Hit Ratio..."
#            HIT_RATIO=$($PG_OUT/bin/psql -p 8000 -U $PG_USER -d $PG_DB -t -c "
#                SELECT relname AS items_embedding_idx, idx_blks_hit, idx_blks_read,
#                       ROUND(100.0 * idx_blks_hit / NULLIF(idx_blks_hit + idx_blks_read, 0), 2) AS index_hit_ratio
#                FROM pg_statio_user_indexes
#                ORDER BY index_hit_ratio DESC;
#            ")
#
#            echo "Index Hit Ratio for shared_buffers=${SHARED_BUFFERS}B ($BUFFER_RATIO%), Build Ratio=${BUILD_RATIO}%, Pool Ratio=${POOL_RATIO_LOG}:" >> $LOG_FILE
#            echo "$HIT_RATIO" >> $LOG_FILE
#
#
#            echo "---------------------------------" >> $LOG_FILE
#        done
#
#
#        sed -i 's|^\(\s*\)//\s*\(HnswInsertTupleOnDiskWithPartition(index, &support, value, heaptid, false);\)|\2|; s|^\(\s*\)\(HnswInsertTupleOnDisk(index, &support, value, heaptid, false);\)|\1// \2|' $SOURCE_INSERT_FILE


    done
done

$PG_OUT/bin/pg_ctl -D $PG_OUT/pgdb stop -o "-p $PG_PORT"
sleep 3

echo "Experiment completed. Results saved in $LOG_FILE."