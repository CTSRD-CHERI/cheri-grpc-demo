#!/bin/bash

set -e

#
# Helper script to run the qps benchmark.
# This assumes that benchmark results should be stored at /root/results
#
if [ -z "${QPS_JAIL_ABI_SUFFIX}" ]; then
    echo "ERROR: missing QPS_JAIL_ABI_SUFFIX env var"
    exit 1
fi
QPS_PACKAGE="${QPS_PACKAGE:=grpc-qps-1.54.2,2.pkg}"

OPTSTRING="n"
X=

function usage()
{
    echo "$0 - Run the Morello gRPC qps benchmark"
    echo "Options":
    echo -e "\t-h\tShow help message"
    echo -e "\t-n\tPretend run, print the commands without doing anything"
    exit 1
}

while getopts ${OPTSTRING} opt; do
    case ${opt} in
        h)
            usage
            ;;
        n)
            X="echo"
            ;;
        :)
            echo "Option -${OPTARG} requires an argument"
            usage
            ;;
        ?)
        echo "Invalid option -${OPTARG}"
        usage
        ;;
    esac
done

echo "=== QPS run configuration ==="

QPS_SCENARIOS=/usr/local64cb/share/grpc-qps/scenarios
QPS_RESULTS_DIR=/root/results

QPS_SCENARIO_PREFIX=scenario_dump_cpp_
QPS_SCENARIO_LIST=(protobuf_async_streaming_qps_unconstrained_insecure)
QPS_ITERATIONS=5

echo "QPS_ITERATIONS:   ${QPS_ITERATIONS}"
echo "QPS_CONFIGS:      ${QPS_SCENARIO_LIST}"
echo "QPS_RESULTS_DIR:  ${QPS_RESULTS_DIR}"

echo "=== Setup grpc-qps packages ==="
${X} env ASSUME_ALWAYS_YES=yes pkg64 install python39 py39-six
${X} env ASSUME_ALWAYS_YES=yes pkg${QPS_JAIL_ABI_SUFFIX} add /packages/All/${QPS_PACKAGE}

echo "=== Setup benchmark ==="
echo "Start port server..."
${X} grpc_qps_port_server

echo "Start qps workers..."
W0_PORT=10000
W1_PORT=10001

${X} grpc_qps_worker --driver_port=${W0_PORT} &
WORKER0_PID=$!
${X} grpc_qps_worker --driver_port=${W1_PORT} &
WORKER1_PID=$!
export QPS_WORKERS=localhost:${W0_PORT},localhost:${W1_PORT}

echo "Worker 0: PID ${WORKER0_PID}"
echo "Worker 1: PID ${WORKER1_PID}"
# Wait for the workers to settle a bit
sleep 1

# $1 => iteration number
# $2 => scenario name
function run_qps()
{
    iteration=${1}
    name=${2}
    fullname="${QPS_SCENARIO_PREFIX}${name}.json"

    ${X} grpc_qps_json_driver \
        --scenarios_file "${QPS_SCENARIOS}/${fullname}" \
        --json_file_out "${QPS_RESULTS_DIR}/summary_${name}.${iteration}.json"
}

# $1 => scenario name
function run_scenario()
{
    name=${1}
    echo "+++ Scenario ${name} +++"
    for i in $(seq 1 ${QPS_ITERATIONS}); do
        run_qps ${i} ${name}
    done
    echo "--- Scenario ${name} ---"
}

echo "=== Begin benchmark loop ==="
for scenario in ${QPS_SCENARIO_LIST[@]}; do
    run_scenario ${scenario}
done

${X} pkill grpc_qps_worker
