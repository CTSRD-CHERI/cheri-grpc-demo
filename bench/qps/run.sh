#!/usr/local64/bin/bash

#
# Helper script to run the qps benchmark.
# This assumes that benchmark results should be stored at /root/results
#

set -e

QPS_PACKAGE_FLAVOR=
QPS_PACKAGE_ABI=invalid
QPS_EXPERIMENT=base
QPS_ITERATIONS=10
QPS_SCENARIO_GROUP=async
QPS_SCENARIO_SUFFIX=
# Assume that the QPS benchmark data and scripts are mounted at /root/qps
CURDIR="/root/qps"

C18N_INTERP=
C18N_POLICY=
RTLD_ENV_PREFIX=
PERSISTENT_WORKERS=
HWPMC_SAMPLING=
HWPMC_COUNTING=
HWPMC_COMMAND=

OPTSTRING="na:r:i:f:g:dv:j:J:V"
X=

function usage()
{
    echo "$0 - Run the Morello gRPC qps benchmark"
    echo "Options":
    echo -e "\t-a\tABI of the QPS benchmark to run, this must match the installed package abi"
    echo -e "\t-d\tDo not respawn qps workers for each iteration"
    echo -e "\t-f\tUse fixed-size workload instead of fixed-time, give the scenario suffix"
    echo -e "\t-g\tBenchmark group, one of async,async_tls,async_pp,sync,sync_tls,sync_pp"
    echo -e "\t-h\tShow help message"
    echo -e "\t-i\tIterations, default 10"
    echo -e "\t-j\tEnable hwpmc profiling in sampling mode at the given rate"
    echo -e "\t-J\tEnable the given counters for hwpmc profiling in counting mode"
    echo -e "\t-n\tPretend run, print the commands without doing anything"
    echo -e "\t-r\tRuntime benchmark configuration, valid options are c18n, revoke"
    echo -e "\t-v\tBuild variant of the QPS benchmark to run, this must match the package flavor"
    echo -e "\t-V\tEnable verbose diagnostics output"

    exit 1
}

# $1 => unique name for this iteration within the results dir, used for pmcstat files
function start_workers()
{
    local pmcname="${1}"
    local envcmd=""
    local hwpmc_cmd="${HWPMC_COMMAND}"

    if [ -n "${C18N_POLICY}" ]; then
        envcmd="env ${RTLD_ENV_PREFIX}COMPARTMENT_POLICY=${C18N_POLICY}"
    elif [ "${QPS_EXPERIMENT}" == "c18n_ipc" ]; then
        envcmd="env ${RTLD_ENV_PREFIX}COMPARTMENT_OVERHEAD=1"
    fi

    if [ -n "${HWPMC_SAMPLING}" ]; then
        hwpmc_cmd+=" -O ${QPS_RESULTS_DIR}/${pmcname}.pmc.stat"
    fi
    if [ -n "${HWPMC_COUNTING}" ]; then
        hwpmc_cmd+=" -o ${QPS_RESULTS_DIR}/${pmcname}.pmc.txt"
    fi

    # Note that the server worker will always be the last one.
    # The qps driver allocates first servers, than clients, however
    # the QPS_WORKERS env var is reversed when parsing.

    echo "Start qps workers..."
    if [ -z "${X}" ]; then
        ${envcmd} grpc_qps_worker --driver_port=${W0_PORT} &
        WORKER0_PID=$!
        ${envcmd} ${hwpmc_cmd} grpc_qps_worker --driver_port=${W1_PORT} &
        WORKER1_PID=$!
    else
        # Run in pretend mode
        echo "${envcmd} grpc_qps_worker --driver_port=${W0_PORT}"
        WORKER0_PID="<WORKER0_PID>"
        echo "${envcmd} ${hwpmc_cmd} grpc_qps_worker --driver_port=${W1_PORT}"
        WORKER1_PID="<WORKER1_PID>"
    fi
    if [ -n "${HWPMC_COMMAND}" ]; then
        HWPMC_PID=${WORKER1_PID}
    fi

    export QPS_WORKERS=localhost:${W0_PORT},localhost:${W1_PORT}
    # Wait for the workers to settle a bit before starting
    ${X} sleep 1

    echo "Worker 0: PID ${WORKER0_PID}"
    echo "Worker 1: PID ${WORKER1_PID}"
}

# $1 => unique name for this iteration within the results dir, used for pmcstat files
function stop_workers()
{
    local pmcname="${1}"

    ${X} pkill -TERM grpc_qps_worker

    if [ -n "${HWPMC_COMMAND}" ]; then
        ${X} pwait ${HWPMC_PID}
    fi

    if [ -n "${HWPMC_SAMPLING}" ]; then
        # Dump the pmcstats to the correct file
        # Should we do this after everything to limit noise between iterations?
        ${X} pmcstat -R "${QPS_RESULTS_DIR}/${pmcname}.pmc.stat" -G \
             "${QPS_RESULTS_DIR}/${pmcname}.pmc.stacks"
        ${X} rm "${QPS_RESULTS_DIR}/${pmcname}.pmc.stat"
    fi
}

# $1 => iteration number
# $2 => scenario name
function run_qps()
{
    local iteration=${1}
    local name=${2}
    local fullname="${name}.json"
    local pmcname="${name}.${iteration}"

    if [ -z "${PERSISTENT_WORKERS}" ]; then
        start_workers ${pmcname}
    fi

    ${X} grpc_qps_json_driver \
        --scenarios_file "${QPS_SCENARIOS}/${fullname}" \
        --scenario_result_file "${QPS_RESULTS_DIR}/summary_${name}.${iteration}.json"

    if [ -z "${PERSISTENT_WORKERS}" ]; then
        stop_workers ${pmcname}
    fi
}

# $1 => scenario name
function run_scenario()
{
    name=${1}
    echo "+++ Scenario ${name} ${QPS_ITERATIONS} iterations +++"
    for i in $(seq 1 ${QPS_ITERATIONS}); do
        run_qps ${i} ${name}
    done
    echo "--- Scenario ${name} ---"
}

while getopts ${OPTSTRING} opt; do
    case ${opt} in
        h)
            usage
            ;;
        n)
            X="echo"
            BACKGROUND=""
            ;;
        a)
            QPS_PACKAGE_ABI=${OPTARG}
            ;;
        r)
            QPS_EXPERIMENT=${OPTARG}
            ;;
        i)
            QPS_ITERATIONS=${OPTARG}
            ;;
        f)
            QPS_SCENARIO_SUFFIX="_${OPTARG}"
            ;;
        g)
            QPS_SCENARIO_GROUP=${OPTARG}
            ;;
        j)
            HWPMC_SAMPLING=${OPTARG}
            ;;
        J)
            HWPMC_COUNTING=${OPTARG}
            ;;
        d)
            PERSISTENT_WORKERS=1
            ;;
        v)
            if [ "${OPTARG}" != "base" ]; then
                QPS_PACKAGE_FLAVOR="-${OPTARG}"
            fi
            ;;
        V)
            export GRPC_VERBOSITY="DEBUG"
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

if [ -n "${HWPMC_SAMPLING}" ] || [ -n "${HWPMC_COUNTING}" ]; then
    pmc_args=""
    if [ -n "${HWPMC_SAMPLING}" ]; then
        pmc_args+=" -P INST_RETIRED -n ${HWPMC_SAMPLING}"
    fi
    if [ -n "${HWPMC_COUNTING}" ]; then
        for pmc in `echo ${HWPMC_COUNTING} | tr "," "\n"`; do
            pmc_args+=" -p ${pmc}"
        done
    fi
    HWPMC_COMMAND="pmcstat ${pmc_args}"
fi

echo "=== QPS run configuration ==="

case "${QPS_PACKAGE_ABI}" in
    invalid)
        echo "ERROR: missing -a option"
        exit 1
        ;;
    hybrid)
        PREFIX=/usr/local64
        PKG=pkg64
        C18N_INTERP=
        RTLD_ENV_PREFIX=
        ;;
    purecap)
        PREFIX=/usr/local
        PKG=pkg64c
        C18N_INTERP=/libexec/ld-elf-c18n.so.1
        RTLD_ENV_PREFIX="LD_"
        ;;
    benchmark)
        PREFIX=/usr/local64cb
        PKG=pkg64cb
        C18N_INTERP=/libexec/ld-elf64cb-c18n.so.1
        RTLD_ENV_PREFIX="LD_64CB_"
        ;;
    *)
        echo "ERROR: invalid -a option, must be {hybrid, purecap, benchmark}"
        exit 1
esac

QPS_PACKAGE="grpc-qps${QPS_PACKAGE_FLAVOR}-1.54.2,2.pkg"
QPS_SCENARIOS="${CURDIR}/scenarios/gen"
QPS_RESULTS_DIR="/root/results/grpc-${QPS_PACKAGE_ABI}${QPS_PACKAGE_FLAVOR:=-base}/${QPS_EXPERIMENT}"

QPS_SCENARIO_PREFIX=qps_

case "${QPS_SCENARIO_GROUP}" in
    sync)
        QPS_SCENARIO_LIST=(sync_streaming_insecure_262144b \
            sync_streaming_insecure_32768b \
            sync_streaming_insecure_4096b \
            sync_streaming_insecure_512b \
            sync_streaming_insecure_64b \
            sync_streaming_insecure_8b \
            sync_streaming_insecure_1b)
        ;;
    sync_tls)
        QPS_SCENARIO_LIST=(sync_streaming_secure_262144b \
            sync_streaming_secure_32768b \
            sync_streaming_secure_4096b \
            sync_streaming_secure_512b \
            sync_streaming_secure_64b \
            sync_streaming_secure_8b \
            sync_streaming_secure_1b)
        ;;
    sync_pp)
        QPS_SCENARIO_LIST=(sync_streaming_ping_pong_insecure \
            sync_streaming_ping_pong_secure \
            sync_unary_ping_pong_insecure \
            sync_unary_ping_pong_secure)
        ;;
    async)
        QPS_SCENARIO_LIST=(async_streaming_insecure_262144b \
            async_streaming_insecure_32768b \
            async_streaming_insecure_4096b \
            async_streaming_insecure_512b \
            async_streaming_insecure_64b \
            async_streaming_insecure_8b \
            async_streaming_insecure_1b)
        ;;
    async_tls)
        QPS_SCENARIO_LIST=(async_streaming_secure_262144b \
            async_streaming_secure_32768b \
            async_streaming_secure_4096b \
            async_streaming_secure_512b \
            async_streaming_secure_64b \
            async_streaming_secure_8b \
            async_streaming_secure_1b)
        ;;
    async_pp)
        QPS_SCENARIO_LIST=(async_streaming_ping_pong_insecure \
            async_streaming_ping_pong_secure \
            async_unary_ping_pong_insecure \
            async_unary_ping_pong_secure)
        ;;
    async_dasa)
        QPS_SCENARIO_LIST=(async_streaming_insecure_8b \
            async_streaming_insecure_64b \
            async_streaming_secure_8b \
            async_streaming_secure_64b)
        ;;
    *)
        echo "Invalid scenario group selection"
        exit 1
esac

for idx in ${!QPS_SCENARIO_LIST[@]}; do
    QPS_SCENARIO_LIST[idx]="${QPS_SCENARIO_PREFIX}${QPS_SCENARIO_LIST[idx]}${QPS_SCENARIO_SUFFIX}"
done

if [ "$default_revoke" == "1" ]; then
    echo "ERROR: Runtime revocation is enabled by default, disable now"
    exit 1
fi

echo "=== Setup grpc-qps packages ==="
if [ "${QPS_PACKAGE_ABI}" == "hybrid" ]; then
    PKGDIR="/packages64"
else
    PKGDIR="/packages"
fi
${X} env ASSUME_ALWAYS_YES=yes ${PKG} add ${PKGDIR}/All/${QPS_PACKAGE}

case "${QPS_EXPERIMENT}" in
    base)
        ;;
    c18n|c18n_policy|c18n_ipc)
        if [ -z "${C18N_INTERP}" ]; then
           echo "ERROR: can not use -r c18n with -a hybrid"
           exit 1
        fi
        echo "Patch QPS to enable c18n"
        ${X} patchelf --set-interpreter "${C18N_INTERP}" "${PREFIX}/bin/grpc_qps_worker"

        if [ "${QPS_EXPERIMENT}" == "c18n_policy" ]; then
            C18N_POLICY="${CURDIR}/policy.txt"
        fi

        RTLD_ENV_PREFIX+="C18N_"
        ;;
    revoke)
        echo "Patch QPS to enable revocation"
        ${X} elfctl -e +cherirevoke "${PREFIX}/bin/grpc_qps_worker"
        ;;
    *)
        echo "ERROR: invalid -r option, must be one of {base, c18n, c18n_policy, c18n_ipc, revoke}"
        exit 1
esac

echo "QPS_PACKAGE:      ${QPS_PACKAGE}"
echo "QPS_ITERATIONS:   ${QPS_ITERATIONS}"
echo "QPS_CONFIGS:      ${QPS_SCENARIO_LIST[@]}"
echo "QPS_RESULTS_DIR:  ${QPS_RESULTS_DIR}"
# Check whether runtime revocation is enabeld by default, we only want revocation explicitly
default_revoke=$(sysctl -n security.cheri.runtime_revocation_default)
echo "DEFAULT REVOKE:   ${default_revoke}"
echo "QPS_C18N_POLICY:  ${C18N_POLICY}"

${X} mkdir -p ${QPS_RESULTS_DIR}

echo  "Dump binary ELF control note:"
${X} elfctl -l "${PREFIX}/bin/grpc_qps_worker"
echo  "Dump binary ELF interp:"
${X} patchelf --print-interpreter "${PREFIX}/bin/grpc_qps_worker"

echo "=== Setup benchmark ==="
echo "Start port server..."
${X} grpc_qps_port_server

W0_PORT=20000
W1_PORT=20001

# Terminate any stragglers
${X} pkill grpc_qps_worker || true

if [ ! -z "${PERSISTENT_WORKERS}" ]; then
    start_workers "all"
fi

echo "=== Begin benchmark loop ==="
for scenario in ${QPS_SCENARIO_LIST[@]}; do
    run_scenario ${scenario}
done

${X} pkill grpc_qps_worker
