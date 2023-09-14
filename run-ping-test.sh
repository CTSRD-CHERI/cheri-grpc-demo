#!/bin/sh

BUILD_DIR=${BUILD_DIR:=./out}

echo "Start ping server"

${BUILD_DIR}/c18n_ping_server &
SERVER_PID=$!

# time ${BUILD_DIR}/c18n_ping_server

export LD_C18N_UTRACE_COMPARTMENT=1

echo "Test ping without policy"

ktrace -f ping-no-policy.ktrace -t u ${BUILD_DIR}/c18n_ping_client

echo "Test ping with policy"
export LD_C18N_PRELOAD=${BUILD_DIR}/libpolicy.so
ktrace -f ping-with-policy.ktrace -t u ${BUILD_DIR}/c18n_ping_client

echo "Teardown"
kill $SERVER_PID

kdump -f ping-no-policy.ktrace > ping-no-policy.txt
kdump -f ping-with-policy.ktrace > ping-with-policy.txt

NUM_NO_POLICY=$(cat ping-no-policy.txt | grep enter | wc -l)
NUM_WITH_POLICY=$(cat ping-with-policy.txt | grep enter | wc -l)

echo "Number of transitions: no-policy:${NUM_NO_POLICY} with-policy:${NUM_WITH_POLICY}"
