#!/usr/local64/bin/bash

#
# Helper script to run the qps benchmark.
# This assumes that benchmark results should be stored at /root/results
#

set -e

QPS_PACKAGE="${QPS_PACKAGE:=grpc-qps-1.54.2,2.pkg}"
QPS_PACKAGE_ABI=invalid
QPS_EXPERIMENT=base

INTERP=

OPTSTRING="na:r:"
X=

function usage()
{
    echo "$0 - Run the Morello gRPC qps benchmark"
    echo "Options":
    echo -e "\t-h\tShow help message"
    echo -e "\t-n\tPretend run, print the commands without doing anything"
    echo -e "\t-a\tABI of the QPS benchmark to run, this must match the installed package abi"
    echo -e "\t-r\tRuntime benchmark configuration, valid options are c18n, revoke"
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
        a)
            QPS_PACKAGE_ABI=${OPTARG}
            ;;
        r)
            QPS_EXPERIMENT=${OPTARG}
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

case "${QPS_PACKAGE_ABI}" in
    invalid)
        echo "ERROR: missing -a option"
        exit 1
        ;;
    hybrid)
        PREFIX=/usr/local64
        PKG=/usr/local64/sbin/pkg
        C18N_INTERP=
        ;;
    purecap)
        PREFIX=/usr/local
        PKG=pkg64c
        C18N_INTERP=/libexec/ld-elf-c18n.so.1
        ;;
    benchmark)
        PREFIX=/usr/local64cb
        PKG=pkg64cb
        C18N_INTERP=/libexec/ld-elf64cb-c18n.so.1
        ;;
    *)
        echo "ERROR: invalid -a option, must be {hybrid, purecap, benchmark}"
        exit 1
esac

QPS_SCENARIOS="${PREFIX}/share/grpc-qps/scenarios"
QPS_RESULTS_DIR="/root/results/${QPS_EXPERIMENT}"

QPS_SCENARIO_PREFIX=scenario_dump_cpp_
QPS_SCENARIO_LIST=(protobuf_sync_streaming_qps_unconstrained_secure \
                   protobuf_sync_streaming_qps_unconstrained_secure_1073741824b \
                   protobuf_sync_streaming_qps_unconstrained_secure_134217728b \
                   protobuf_sync_streaming_qps_unconstrained_secure_16777216b \
                   protobuf_sync_streaming_qps_unconstrained_secure_2097152b \
                   protobuf_sync_streaming_qps_unconstrained_secure_262144b \
                   protobuf_sync_streaming_qps_unconstrained_secure_32768b \
                   protobuf_sync_streaming_qps_unconstrained_secure_4096b \
                   protobuf_sync_streaming_qps_unconstrained_secure_512b \
                   protobuf_sync_streaming_qps_unconstrained_secure_64b \
                   protobuf_sync_streaming_qps_unconstrained_secure_8b \
                   protobuf_sync_streaming_qps_unconstrained_secure_1b \
                   protobuf_sync_streaming_qps_unconstrained_insecure \
                   protobuf_sync_streaming_qps_unconstrained_insecure_1073741824b \
                   protobuf_sync_streaming_qps_unconstrained_insecure_134217728b \
                   protobuf_sync_streaming_qps_unconstrained_insecure_16777216b \
                   protobuf_sync_streaming_qps_unconstrained_insecure_2097152b \
                   protobuf_sync_streaming_qps_unconstrained_insecure_262144b \
                   protobuf_sync_streaming_qps_unconstrained_insecure_32768b \
                   protobuf_sync_streaming_qps_unconstrained_insecure_4096b \
                   protobuf_sync_streaming_qps_unconstrained_insecure_512b \
                   protobuf_sync_streaming_qps_unconstrained_insecure_64b \
                   protobuf_sync_streaming_qps_unconstrained_insecure_8b \
                   protobuf_sync_streaming_qps_unconstrained_insecure_1b)
QPS_ITERATIONS=10


echo "QPS_ITERATIONS:   ${QPS_ITERATIONS}"
echo "QPS_CONFIGS:      ${QPS_SCENARIO_LIST}"
echo "QPS_RESULTS_DIR:  ${QPS_RESULTS_DIR}"
# Check whether runtime revocation is enabeld by default, we only want revocation explicitly
default_revoke=$(sysctl -n security.cheri.runtime_revocation_default)
echo "DEFAULT REVOKE:   ${default_revoke}"

if [ "$default_revoke" == "1" ]; then
    echo "ERROR: Runtime revocation is enabled by default, disable now"
    exit 1
fi

echo "=== Setup grpc-qps packages ==="
${X} env ASSUME_ALWAYS_YES=yes ${PKG} add /packages/All/${QPS_PACKAGE}

case "${QPS_EXPERIMENT}" in
    base)
        ;;
    c18n)
        if [ -z "${INTERP}" ]; then
           echo "ERROR: can not use -r c18n with -a hybrid"
        fi
        echo "Patch QPS to enable c18n"
        ${X} patchelf --set-interpreter "${C18N_INTERP}" "${PREFIX}/bin/grpc_qps_worker"
        ;;
    revoke)
        echo "Patch QPS to enable revocation"
        ${X} elfctl -e +cherirevoke "${PREFIX}/bin/grpc_qps_worker"
        ;;
    *)
        echo "ERROR: invalid -r option, must be {base, c18n, revoke}"
        exit 1
esac

${X} mkdir -p ${QPS_RESULTS_DIR}

echo  "Dump binary ELF control note:"
${X} elfctl -l "${PREFIX}/bin/grpc_qps_worker"
echo  "Dump binary ELF interp:"
${X} patchelf --print-interpreter "${PREFIX}/bin/grpc_qps_worker"

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
        --scenario_result_file "${QPS_RESULTS_DIR}/summary_${name}.${iteration}.json"
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
