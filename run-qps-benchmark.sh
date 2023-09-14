#!/bin/sh

GRPC_BUILD_DIR="${GRPC_BUILD_DIR:=grpc-out}"
GRPC_SCENARIO_DIR="${GRPC_SCENARIO_DIR:=grpc-test-scenarios}"
GRPC_C18N_POLICY="${GRPC_C18N_POLICY:=}"
GRPC_C18N_TRACE="${GRPC_C18N_TRACE:=}"

if [ "${GRPC_C18N_POLICY}" != "" ]; then
    echo "Use policy ${GRPC_C18N_POLICY}"
    export LD_C18N_PRELOAD="${GRPC_C18N_POLICY}"
fi

if [ "${GRPC_C18N_TRACE}" == "" ]; then
    echo "C18N tracing disabled"
    KTRACE_WORKER_0=""
    KTRACE_WORKER_1=""
    KTRACE_DRIVER=""
else
    echo "C18N tracing enabled"
    KTRACE_WORKER_0="ktrace -t u -f ${GRPC_C18N_TRACE}/worker0.ktrace"
    KTRACE_WORKER_1="ktrace -t u -f ${GRPC_C18N_TRACE}/worker1.ktrace"
    KTRACE_DRIVER="ktrace -t u -f ${GRPC_C18N_TRACE}/driver.ktrace"
    export LD_C18N_UTRACE_COMPARTMENT=1
fi

run_qps() {
    echo "Start qps workers..."
    ${KTRACE_WORKER_0} ${GRPC_BUILD_DIR}/qps_worker --driver_port=10000 &
    WORKER_0=$!
    ${KTRACE_WORKER_1} ${GRPC_BUILD_DIR}/qps_worker --driver_port=10001 &
    WORKER_1=$!

    echo "Run qps scenario"
    sleep 1
    export QPS_WORKERS=localhost:10000,localhost:10001
    ${KTRACE_DRIVER} ${GRPC_BUILD_DIR}/qps_json_driver --scenarios_file ${GRPC_SCENARIO_DIR}/c++_scenario_cpp_generic_async_streaming_ping_pong_insecure.json

    echo "Stopping qps workers"
    kill -INT $WORKER_0 $WORKER_1

    if [ "${GRPC_C18N_TRACE}" != "" ]; then
	echo "Dump grpc compartment traces"
	kdump -f ${GRPC_C18N_TRACE}/worker0.ktrace > ${GRPC_C18N_TRACE}/worker0.dump
	kdump -f ${GRPC_C18N_TRACE}/worker1.ktrace > ${GRPC_C18N_TRACE}/worker1.dump
	kdump -f ${GRPC_C18N_TRACE}/driver.ktrace > ${GRPC_C18N_TRACE}/driver.dump
    fi
}

run_qps

unset LD_C18N_PRELOAD
