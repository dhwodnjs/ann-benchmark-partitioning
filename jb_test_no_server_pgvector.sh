#!/bin/bash

# Ensure the script is being run with at least one argument
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 arg1 arg2 ..."
    exit 1
fi

# Define the server control commands and the configuration file path
#PG_OUT="/home/smrc/samsung-nvme/workspace/pg_out"
PG_OUT="/home/jaewonoh/mnt/samsung-nvme/jaewonoh/workspace/pg_out_final_io/"

PG_DATA="$PG_OUT/pgdb_0707"
PG_BIN="$PG_OUT/bin"
PG_CTL="$PG_BIN/pg_ctl"

#CONFIG_FILE="/home/smrc/workspace/ann-benchmark/ann_benchmarks/algorithms/pgvector/config.yml"
CONFIG_FILE="/home/jaewonoh/workspace/ann-benchmark/ann_benchmarks/algorithms/pgvector/config.yml"
#DATA="gist-960-euclidean"
#DATA="dbpedia-openai-100k-angular"
#DATA="dbpedia-openai-1000k-angular"
#DATA="dbpedia-openai-1000k-angular-ivf"
#DATA="dbpedia-openai-100k-angular"
#DATA="nytimes-256-angular"
#DATA="nytimes-16-angular"
#DATA="wikipedia-22-12-angular"
#DATA="glove-200-angular"

#DATA="dbpedia-openai-1000k-angular"
DATA="deep-image-96-angular"
#DATA="coco-i2i-512-angular"
#DATA="glove-200-angular"
#DATA="sift-128-angular"
#DATA=

#if data ends with -ivf, get rid of the suffix
if [[ $DATA == *-ivf ]]; then
    # Remove the '-ivf' suffix
    DATA=${DATA%-ivf}
fi

# Function to stop the PostgreSQL server

stop_server() {
    cd $PG_BIN
    $PG_CTL -D $PG_DATA stop
}

# Function to start the PostgreSQL server
start_server() {
    cd $PG_BIN
    $PG_CTL -D $PG_DATA start
}

# Function to update the configuration file
update_config() {
    local query_value="$1"
    sed -i "s/^\( *query_args: \[\[\).*\(\]\]\)/\1$query_value\2/" $CONFIG_FILE
}

ADD_PARAM=''
#ADD_PARAM=' --count 40'
# Run Test
run_ann_benchmark() {
  cd /home/jaewonoh/workspace/ann-benchmark/
  rm -rf results/*;
  python3 run.py --algorithm pgvector --dataset $DATA --runs 1 --local $ADD_PARAM;
  echo "python3 run.py --algorithm pgvector --dataset $DATA --runs 1 --local $ADD_PARAM;"
  python3 plot.py --dataset $DATA $ADD_PARAM;
}

joined=$(printf ", %s" "$@")
joined=${joined:2}  # Remove leading ", "

echo "\"$joined\""

echo "Processing with query_arg: $joined"
update_config "$joined"
run_ann_benchmark
echo "↑↑↑↑↑↑ ef_search: $joined ↑↑↑↑↑↑"
echo ""
echo ""
echo ""
