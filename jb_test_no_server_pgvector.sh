#!/bin/bash

# Ensure the script is being run with at least one argument
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 arg1 arg2 ..."
    exit 1
fi

# Define the server control commands and the configuration file path
PG_BIN="/home/snu-vldb/workspace/pg_out/bin"
PG_CTL= $PG_BIN + "/bin"
PG_DATA="/home/snu-vldb/workspace/pg_out/pgdb"
CONFIG_FILE="/home/snu-vldb/workspace/ann-benchmarks/ann_benchmarks/algorithms/pgvector/config.yml"
#DATA="gist-960-euclidean"
#DATA="dbpedia-openai-100k-angular"
DATA="dbpedia-openai-1000k-angular"
#DATA="dbpedia-openai-1000k-angular-ivf"
#DATA="dbpedia-openai-100k-angular"

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
  cd /home/snu-vldb/workspace/ann-benchmarks
  rm -rf results/*;
  python3 run.py --algorithm pgvector --dataset $DATA --runs 1 --local $ADD_PARAM;
  echo "python3 run.py --algorithm pgvector --dataset $DATA --runs 1 --local $ADD_PARAM;"
  python3 plot.py --dataset $DATA $ADD_PARAM;
}

# Main loop to process each argument
for arg in "$@"; do
    echo "Processing with query_arg: $arg"

    # Stop the server
#    stop_server

    # Start the server
#    start_server

    # Update the configuration file
    update_config "$arg"

    # Run the command
    run_ann_benchmark
    echo "↑↑↑↑↑↑ ef_search: $arg ↑↑↑↑↑↑"
    echo ""
    echo ""
    echo ""

#    stop_server
done
