#!/bin/sh

GRPC_BUILD_DIR="${GRPC_BUILD_DIR:=grpc-out}"
GRPC_SCENARIO_DIR="${GRPC_SCENARIO_DIR:=grpc-test-scenarios}"
GRPC_C18N_POLICY="${GRPC_C18N_POLICY:=}"
GRPC_C18N_TRACE="${GRPC_C18N_TRACE:=}"
GRPC_C18N_OVERHEAD="${GRPC_C18N_OVERHEAD:=}"
GRPC_BENCHMARK_OUT_DIR="${GRPC_BENCHMARK_OUT_DIR:=${PWD}}"

# GRPC_SCENARIO_NAME="scenario_cpp_generic_async_streaming_ping_pong_insecure.json"
# GRPC_SCENARIO_NAME="scenario_cpp_generic_async_streaming_ping_pong_secure.json"
# GRPC_SCENARIO_NAME="scenario_cpp_protobuf_async_streaming_ping_pong_insecure.json"
# GRPC_SCENARIO_NAME="scenario_cpp_protobuf_async_streaming_ping_pong_secure.json"
GRPC_SCENARIO_NAME="scenario_cpp_protobuf_async_streaming_qps_unconstrained_insecure.json"
# GRPC_SCENARIO_NAME="scenario_cpp_protobuf_async_streaming_qps_unconstrained_secure.json"
# GRPC_SCENARIO_NAME="scenario_cpp_protobuf_async_streaming_qps_unconstrained_insecure_16777216b.json"

GRPC_SCENARIO="${GRPC_SCENARIO_DIR}/${GRPC_SCENARIO_NAME}"

if [ "${GRPC_C18N_POLICY}" != "" ]; then
    echo "Use policy ${GRPC_C18N_POLICY}"
    export LD_C18N_PRELOAD="${GRPC_C18N_POLICY}"
fi

if [ "${GRPC_C18N_OVERHEAD}" != "" ]; then
    echo "Enable C18N IPC overhead simulation"
    export LD_C18N_COMPARTMENT_OVERHEAD=1
fi

if [ "${GRPC_C18N_TRACE}" == "" ]; then
    echo "C18N tracing disabled"
    KTRACE_WORKER_0="/libexec/ld-elf.so.1"
    KTRACE_WORKER_1="/libexec/ld-elf.so.1"
else
    echo "C18N tracing enabled"
    KTRACE_WORKER_0="ktrace -t u -f ${GRPC_C18N_TRACE}/worker0.ktrace"
    KTRACE_WORKER_1="ktrace -t u -f ${GRPC_C18N_TRACE}/worker1.ktrace"
    export LD_C18N_UTRACE_COMPARTMENT=1
fi

W0_PORT=10000
W1_PORT=10001

run_qps() {
    echo "Start qps workers..."
    ${KTRACE_WORKER_0} ${GRPC_BUILD_DIR}/qps_worker --driver_port=${W0_PORT} &
    WORKER_0=$!
    ${KTRACE_WORKER_1} ${GRPC_BUILD_DIR}/qps_worker --driver_port=${W1_PORT} &
    WORKER_1=$!

    echo "Run QPS scenario"
    sleep 8
    export QPS_WORKERS=localhost:${W0_PORT},localhost:${W1_PORT}

    ${GRPC_BUILD_DIR}/qps_json_driver \
                     --scenarios_file ${GRPC_SCENARIO} \
                     --json_file_out "${GRPC_BENCHMARK_OUT_DIR}/out_${GRPC_SCENARIO_NAME}"
    sleep 5

    echo "Stopping qps workers"
    kill -INT $WORKER_0 $WORKER_1

    if [ "${GRPC_C18N_TRACE}" != "" ]; then
	echo "Dump grpc compartment traces"
	kdump -f ${GRPC_C18N_TRACE}/worker0.ktrace > ${GRPC_C18N_TRACE}/worker0.dump
	kdump -f ${GRPC_C18N_TRACE}/worker1.ktrace > ${GRPC_C18N_TRACE}/worker1.dump
    fi
}

#for scenario in ${GRPC_SCENARIO_LIST}; do
    for i in $(seq 1 1); do
        run_qps
        W0_PORT=$((W0_PORT + 2))
        W1_PORT=$((W1_PORT + 2))
    done
#done

unset LD_C18N_PRELOAD
