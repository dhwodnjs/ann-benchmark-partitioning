#!/bin/bash

BASE_SHARED_BUFFERS=7168000


RATIOS=(100 90 80 70 60 50 40 30 20 10)

PG_USER="ann"
PG_DB="ann"
PG_NAMESPACE=2200
TABLE_NAME="items"


LOG_FILE="experiment_results_vanilla.log"
DATA_PATH = ""


echo "Starting experiment..." > $LOG_FILE


for DATA_RATIO in "${RATIOS[@]}"; do

    echo "Running build.py with data ratio $DATA_RATIO%..."
    BUILD_TIME=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_build.py --size 10000 --ratio $DATA_RATIO --table_name $TABLE_NAME --data_path $DATA_PATH)

    echo "Running insert.py with data ratio $DATA_RATIO%..."
    INSERT_TIME=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_insert.py --size 10000 --ratio $DATA_RATIO --table_name $TABLE_NAME --data_path $DATA_PATH)

    echo "Resetting PostgreSQL stats..."
    $PG_OUT/bin/psql -U $PG_USER -d $PG_DB -c "SELECT pg_stat_reset();"

    echo "Running ANALYZE..."
    $PG_OUT/bin/psql -U $PG_USER -d $PG_DB -c "ANALYZE;"

    echo "Fetching index and page statistics..."
    INDEX_STATS=$($PG_OUT/bin/psql -U $PG_USER -d $PG_DB -t -c "
        SELECT oid, pg_table_size(oid), relname, relnamespace, reltype, relowner,
               relfilenode, reltablespace, relpages, reltuples, reltoastrelid, relhasindex
        FROM pg_class
        WHERE relnamespace = $PG_NAMESPACE;
    ")

    echo "Index Stats for Data Ratio=${DATA_RATIO}%, Table = $TABLE_NAME:" >> $LOG_FILE
    echo "$INDEX_STATS" >> $LOG_FILE


    echo "Build Time: $BUILD_TIME, Insert Time: $INSERT_TIME" >> $LOG_FILE


    for BUFFER_PERCENT in "${RATIOS[@]}"; do

        SHARED_BUFFERS=$(($BASE_SHARED_BUFFERS * $BUFFER_PERCENT / 100))


        echo "Testing with shared_buffers = ${SHARED_BUFFERS}B ($BUFFER_PERCENT%), Data Ratio = ${DATA_RATIO}%, Table = $TABLE_NAME" >> $LOG_FILE


#        echo "---------------------------------" >> $LOG_FILE
#        echo "Setting shared_buffers to ${SHARED_BUFFERS}B ($BUFFER_PERCENT%)" >> $LOG_FILE

#        echo "Setting shared_buffers to ${SHARED_BUFFERS}B"
        sudo sed -i "s/^shared_buffers = .*/shared_buffers = ${SHARED_BUFFERS}B/" ~/workspace/pg_out/pgdb/postgresql.conf
        $PG_OUT/bin/pg_ctl -D ~/workspace/pg_out/pgdb stop
        sleep 3
        $PG_OUT/bin/pg_ctl -D ~/workspace/pg_out/pgdb start
        sleep 5

        # 버퍼 크기 확인
#        echo "Verifying shared_buffers setting..." >> $LOG_FILE
        CURRENT_BUFFERS=$($PG_OUT/bin/psql -U $PG_USER -d $PG_DB -t -c "SHOW shared_buffers;")

#        echo "Current shared_buffers setting: $CURRENT_BUFFERS" >> $LOG_FILE



        $PG_OUT/bin/psql -U $PG_USER -d $PG_DB -c "select pg_stat_reset();"


#        echo "Running search.py..."
        SEARCH_RESULTS=$(python3 ~/workspace/ann-benchmark/jaewon-test/sh_search.py --table_name $TABLE_NAME --data_path $DATA_PATH)

#        echo "Search Results (Hit Ratio) for shared_buffers=${SHARED_BUFFERS}B ($BUFFER_PERCENT%), Data Ratio=${DATA_RATIO}%, Table = $TABLE_NAME:" >> $LOG_FILE
        echo "$SEARCH_RESULTS" >> $LOG_FILE


#        echo "Fetching Index Hit Ratio..."
        HIT_RATIO=$($PG_OUT/bin/psql -U $PG_USER -d $PG_DB -t -c "
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

echo "Experiment completed. Results saved in $LOG_FILE."
