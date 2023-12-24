#!/usr/local64/bin/bash

#
# Helper script to run the qps benchmark.
# This assumes that benchmark results should be stored at /root/results
#

set -e

CURDIR=$(readlink -f $(dirname "$0"))
NGINX_PACKAGE="${NGINX_PACKAGE:=nginx-1.54.2,2.pkg}"
NGINX_PACKAGE_ABI=invalid
NGINX_EXPERIMENT=base
NGINX_ITERATIONS=10

C18N_INTERP=
PERSISTENT_WORKERS=

OPTSTRING="na:r:i:d"
X=

function usage()
{
    echo "$0 - Run the Morello nginx wrk benchmark"
    echo "Options":
    echo -e "\t-h\tShow help message"
    echo -e "\t-n\tPretend run, print the commands without doing anything"
    echo -e "\t-a\tABI of the QPS benchmark to run, this must match the installed package abi"
    echo -e "\t-r\tRuntime benchmark configuration, valid options are c18n, revoke"
    echo -e "\t-i\tIterations, default 10"
    echo -e "\t-d\tDo not respawn nginx for each iteration"
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
            NGINX_PACKAGE_ABI=${OPTARG}
            ;;
        r)
            NGINX_EXPERIMENT=${OPTARG}
            ;;
        i)
            NGINX_ITERATIONS=${OPTARG}
            ;;
        d)
            PERSISTENT_WORKERS=1
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

echo "=== nginx run configuration ==="

case "${NGINX_PACKAGE_ABI}" in
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

NGINX_RESULTS_DIR="/root/results/${NGINX_EXPERIMENT}"

NGINX_SCENARIO_LIST=(random_0b random_512b random_1024b random_10240b random_102400b)

echo "NGINX_ITERATIONS:   ${NGINX_ITERATIONS}"
echo "NGINX_SCENARIOS:   ${NGINX_SCENARIO_LIST[@]}"
echo "NGINX_RESULTS_DIR:  ${NGINX_RESULTS_DIR}"
# Check whether runtime revocation is enabeld by default, we only want revocation explicitly
default_revoke=$(sysctl -n security.cheri.runtime_revocation_default)
echo "DEFAULT REVOKE:   ${default_revoke}"

if [ "$default_revoke" == "1" ]; then
    echo "ERROR: Runtime revocation is enabled by default, disable now"
    exit 1
fi

echo "=== Setup nginx packages ==="
${X} env ASSUME_ALWAYS_YES=yes ${PKG} add /packages/All/${NGINX_PACKAGE}

NGINX_BINARY="${PREFIX}/sbin/nginx"

case "${NGINX_EXPERIMENT}" in
    base)
        ;;
    c18n)
        if [ -z "${C18N_INTERP}" ]; then
           echo "ERROR: can not use -r c18n with -a hybrid"
           exit 1
        fi
        echo "Patch nginx to enable c18n"
        ${X} patchelf --set-interpreter "${C18N_INTERP}" "${NGINX_BINARY}"
        ;;
    revoke)
        echo "Patch nginx to enable revocation"
        ${X} elfctl -e +cherirevoke "${NGINX_BINARY}"
        ;;
    *)
        echo "ERROR: invalid -r option, must be {base, c18n, revoke}"
        exit 1
esac

${X} mkdir -p ${NGINX_RESULTS_DIR}

echo  "Dump binary ELF control note:"
${X} elfctl -l "${NGINX_BINARY}"
echo  "Dump binary ELF interp:"
${X} patchelf --print-interpreter "${NGINX_BINARY}"

echo "=== Setup benchmark ==="
function start_nginx()
{
    ${X} ${NGINX_BINARY} -c "/root/nginx/nginx.conf"
    sleep 1
    echo "Nginx started at $(cat /usr/local/nginx/logs/nginx.pid)"

function stop_nginx()
{
    ${X} kill -QUIT $(cat /usr/local/nginx/logs/nginx.pid)
}

# $1 => iteration number
# $2 => scenario - the file to fetch with wrk
function run_wrk_one()
{
    iteration=${1}
    name=${2}
    fullname="${name}.bin"

    if [ -z "${PERSISTENT_WORKERS}" ]; then
        start_workers
    fi

    ${X} wrk -t 1 -c 50 -d 5m --latency -s "${CURDIR}/wrk-report.lua" "https://localhost/rps/${fullname}"
    ${X} mv wrk-result.json "${NGINX_RESULTS_DIR}/result_${name}.${iteration}.json"

    if [ -z "${PERSISTENT_WORKERS}" ]; then
        stop_workers
    fi
}

# $1 => scenario - the file to fetch with wrk
function run_wrk()
{
    name=${1}
    echo "+++ Scenario ${name} ${NGINX_ITERATIONS} iterations +++"
    for i in $(seq 1 ${QPS_ITERATIONS}); do
        run_qps ${i} ${name}
    done
    echo "--- Scenario ${name} ---"
}

if [ ! -z "${PERSISTENT_WORKERS}" ]; then
    start_nginx
fi

echo "=== Begin benchmark loop ==="
for scenario in ${NGINX_SCENARIO_LIST[@]}; do
    run_wrk ${scenario}
done
