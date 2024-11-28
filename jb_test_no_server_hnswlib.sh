#!/bin/bash

# Ensure the script is being run with at least one argument
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 arg1 arg2 ..."
    exit 1
fi

# Define the server control commands and the configuration file path

CONFIG_FILE="/home/snu-vldb/workspace/ann-benchmarks/ann_benchmarks/algorithms/hnswlib/config.yml"
ALGORITHM="hnswlib"

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

update_config() {
    local query_value="$1"
    sed -i "s/^\( *query_args: \[\[\).*\(\]\]\)/\1$query_value\2/" $CONFIG_FILE
}

DEFAULT_COUNT=40

ADD_PARAM=''
# Run Test
run_ann_benchmark() {
  cd /home/snu-vldb/workspace/ann-benchmarks
  rm -rf results/*;
  python3 run.py --algorithm $ALGORITHM --dataset $DATA --runs 4 --local $ADD_PARAM;
  echo "python3 run.py --algorithm hnswlib --dataset $DATA --runs 4 --local $ADD_PARAM;"
  python3 plot.py --dataset $DATA $ADD_PARAM;
}

# Main loop to process each argument
for arg in "$@"; do
    echo "Processing with query_arg: $arg"

    # Update the configuration file
    update_config "$arg"

    COUNT=$(( arg < DEFAULT_COUNT ? arg : DEFAULT_COUNT ))
    ADD_PARAM=" --count $COUNT"

    # Run the command
    run_ann_benchmark
    echo "↑↑↑↑↑↑ ef_search: $arg ↑↑↑↑↑↑"
    echo ""
    echo ""
    echo ""
done

