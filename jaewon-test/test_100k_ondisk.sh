#!/bin/bash

BASE_SHARED_BUFFERS=71524352


DATA_RATIOS=(90 80 70 60 50 40 30 20 10)
BUFFER_RATIOS=(50)
PARTITION_SIZES=(64)
POOL_RATIOS=(30)

PG_USER="ann"
PG_DB="ann"
PG_NAMESPACE=2200
PG_OUT=~/mnt/samsung-nvme/jaewonoh/workspace/pg_out

HEAP_TUPLE=100000

TABLE_NAME="items"
DATA_PATH="/home/jaewonoh/workspace/data/deep-image-96-angular.hdf5"
#DATA_PATH="/home/jaewonoh/workspace/data/dbpedia-openai-1000k-angular.hdf5"
#DATA_PATH="/home/jaewonoh/workspace/data/nytimes-256-angular.hdf5"
#DATA_PATH="/home/jaewonoh/workspace/data/glove-200-angular.hdf5"
#DATA_PATH="/home/jaewonoh/workspace/data/gist-960-euclidean.hdf5"
#DATA_PATH="/home/jaewonoh/workspace/data/coco-i2i-512-angular.hdf5"

LOG_NAME="experiment_results_deep_100K"

SOURCE_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnsw.h"
SOURCE_BUILD_FILE="/home/jaewonoh/workspace/git/pgpgpg/pgvector/src/hnswbuild.c"



for DATA_RATIO in "${DATA_RATIOS[@]}"; do


    BUILD_COUNT=$(($HEAP_TUPLE * DATA_RATIO / 100))
    echo "Modifying source code to set build count = BUILD_COUNT"
    sed -i "s/if (graph->indtuples > [0-9]\+)/if (graph->indtuples > $BUILD_COUNT)/" $SOURCE_BUILD_FILE

    #
    for PARTITION_SIZE in "${PARTITION_SIZES[@]}"; do
    #    LOG_FILE="/home/jaewonoh/workspace/ann-benchmark/jaewon-test/${LOG_NAME}_partition_${PARTITION_SIZE}.log"
    #
    #    echo "Starting experiment with partition size $PARTITION_SIZE..." > $LOG_FILE

        echo "Modifying source code to set maxNodesPerPartition = $PARTITION_SIZE"
        sed -i "s/if (graph->indtuples > [0-9]\+)/if (graph->indtuples > $DATA_RATIO)/" $SOURCE_FILE


        #
        for POOL_PERCENT in "${POOL_RATIOS[@]}"; do
#            POOL_SIZE=$(($HEAP_TUPLE * $DATA_RATIO / 100 / $PARTITION_SIZE * POOL_PERCENT / 100))
            POOL_SIZE=$(($HEAP_TUPLE  / $PARTITION_SIZE * POOL_PERCENT / 100))

            LOG_FILE="/home/jaewonoh/workspace/ann-benchmark/jaewon-test/${LOG_NAME}_partition_${PARTITION_SIZE}_pool_${POOL_PERCENT}_static_build_${DATA_RATIO}.log"


            echo "Starting experiment with partition size $PARTITION_SIZE pool size $POOL_SIZE ..." > $LOG_FILE


            echo "Modifying source code to set max_insert_pool_size = $POOL_SIZE"
            sed -i "s/#define MAX_INSERT_POOL_SIZE [0-9]\+/#define MAX_INSERT_POOL_SIZE $POOL_SIZE/" $SOURCE_FILE


            cd /home/jaewonoh/workspace/git/pgpgpg/pgvector

            make PG_CONFIG=/home/jaewonoh/mnt/samsung-nvme/jaewonoh/workspace/pg_out/bin/pg_config clean;
            make PG_CONFIG=/home/jaewonoh/mnt/samsung-nvme/jaewonoh/workspace/pg_out/bin/pg_config -j 32;
            make install PG_CONFIG=/home/jaewonoh/mnt/samsung-nvme/jaewonoh/workspace/pg_out/bin/pg_config;


            $PG_OUT/bin/pg_ctl -D $PG_OUT/pgdb stop -o "-p 8000"
            sleep 3
            $PG_OUT/bin/pg_ctl -D $PG_OUT/pgdb start -o "-p 8000"
            sleep 3


            echo "Running build.py with data ratio $DATA_RATIO%..."
            BUILD_TIME=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_build.py --size $HEAP_TUPLE --ratio 100 --table_name $TABLE_NAME --data_path $DATA_PATH)

#            echo "Running insert.py with data ratio $DATA_RATIO%..."
#            INSERT_TIME=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_insert.py --size $HEAP_TUPLE --ratio $DATA_RATIO --table_name $TABLE_NAME --data_path $DATA_PATH)

            echo "Resetting PostgreSQL stats..."
            $PG_OUT/bin/psql -p 8000 -U $PG_USER -d $PG_DB -c "SELECT pg_stat_reset();"

            echo "Running ANALYZE..."
            $PG_OUT/bin/psql -p 8000 -U $PG_USER -d $PG_DB -c "ANALYZE;"

            echo "Fetching index and page statistics..."
            INDEX_STATS=$($PG_OUT/bin/psql -p 8000 -U $PG_USER -d $PG_DB -t -c "
                SELECT oid, pg_table_size(oid), relname, relnamespace, reltype, relowner,
                       relfilenode, reltablespace, relpages, reltuples, reltoastrelid, relhasindex
                FROM pg_class
                WHERE relnamespace = $PG_NAMESPACE;
            ")

            echo "Index Stats for Data Ratio=${DATA_RATIO}%, Table = $TABLE_NAME:" >> $LOG_FILE
            echo "$INDEX_STATS" >> $LOG_FILE


            echo "Build Time: $BUILD_TIME, Insert Time: $INSERT_TIME" >> $LOG_FILE


            for BUFFER_PERCENT in "${BUFFER_RATIOS[@]}"; do

                SHARED_BUFFERS=$(($BASE_SHARED_BUFFERS * $BUFFER_PERCENT / 100))


                echo "Testing with shared_buffers = ${SHARED_BUFFERS}B ($BUFFER_PERCENT%), Data Ratio = ${DATA_RATIO}%, Table = $TABLE_NAME" >> $LOG_FILE


        #        echo "---------------------------------" >> $LOG_FILE
        #        echo "Setting shared_buffers to ${SHARED_BUFFERS}B ($BUFFER_PERCENT%)" >> $LOG_FILE

        #        echo "Setting shared_buffers to ${SHARED_BUFFERS}B"
                sudo sed -i "s/^shared_buffers = .*/shared_buffers = ${SHARED_BUFFERS}B/" $PG_OUT/pgdb/postgresql.conf
                $PG_OUT/bin/pg_ctl -D $PG_OUT/pgdb stop -o "-p 8000"
                sleep 3
                $PG_OUT/bin/pg_ctl -D $PG_OUT/pgdb start -o "-p 8000"
                sleep 5

                # 버퍼 크기 확인
        #        echo "Verifying shared_buffers setting..." >> $LOG_FILE
                CURRENT_BUFFERS=$($PG_OUT/bin/psql -p 8000 -U $PG_USER -d $PG_DB -t -c "SHOW shared_buffers;")

        #        echo "Current shared_buffers setting: $CURRENT_BUFFERS" >> $LOG_FILE



               $PG_OUT/bin/psql -U $PG_USER -p 8000 -d $PG_DB -c "select pg_stat_reset();"


        #        echo "Running search.py..."
                SEARCH_RESULTS=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_search.py --table_name $TABLE_NAME --data_path $DATA_PATH)

        #        echo "Search Results (Hit Ratio) for shared_buffers=${SHARED_BUFFERS}B ($BUFFER_PERCENT%), Data Ratio=${DATA_RATIO}%, Table = $TABLE_NAME:" >> $LOG_FILE
                echo "$SEARCH_RESULTS" >> $LOG_FILE


        #        echo "Fetching Index Hit Ratio..."
                HIT_RATIO=$($PG_OUT/bin/psql -p 8000 -U $PG_USER -d $PG_DB -t -c "
                    SELECT relname AS items_embedding_idx, idx_blks_hit, idx_blks_read,
                           ROUND(100.0 * idx_blks_hit / NULLIF(idx_blks_hit + idx_blks_read, 0), 2) AS index_hit_ratio
                    FROM pg_statio_user_indexes
                    ORDER BY index_hit_ratio DESC;
                ")

                echo "Index Hit Ratio for shared_buffers=${SHARED_BUFFERS}B ($BUFFER_PERCENT%), Data Ratio=${DATA_RATIO}%, Table = $TABLE_NAME:" >> $LOG_FILE
                echo "$HIT_RATIO" >> $LOG_FILE


                echo "---------------------------------" >> $LOG_FILE
            done
        done
    done
done

$PG_OUT/bin/pg_ctl -D $PG_OUT/pgdb stop -o "-p 8000"
sleep 3

echo "Experiment completed. Results saved in $LOG_FILE."