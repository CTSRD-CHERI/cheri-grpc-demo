#!/usr/local64/bin/bash

#
# Helper script to run the qps benchmark.
# This assumes that benchmark results should be stored at /root/results
#

set -e

CURDIR=$(readlink -f $(dirname "$0"))
NGINX_PACKAGE_ABI=invalid
NGINX_PACKAGE_FLAVOR=
NGINX_EXPERIMENT=base
NGINX_ITERATIONS=10
NGINX_PIDFILE="/var/run/nginx.pid"
NGINX_SCENARIO_GROUP=random

RTLD_ENV_PREFIX=
C18N_INTERP=
PERSISTENT_WORKERS=
WRK_MSGLIMIT=
HWPMC_SAMPLING=
HWPMC_COUNTING=
HWPMC_COMMAND=

OPTSTRING="na:r:g:i:dv:fj:J:V"
X=

function usage()
{
    echo "$0 - Run the Morello nginx wrk benchmark"
    echo "Options":
    echo -e "\t-a\tABI of the nginx server to run, this must match the package abi"
    echo -e "\t-d\tDo not respawn nginx for each iteration"
    echo -e "\t-f\tUse fixed message limit"
    echo -e "\t-g\tBenchmark group, one of random,dasa"
    echo -e "\t-h\tShow help message"
    echo -e "\t-i\tIterations, default 10"
    echo -e "\t-j\tEnable hwpmc profiling in sampling mode at the given rate"
    echo -e "\t-J\tEnable the given counters for hwpmc profiling in counting mode"
    echo -e "\t-n\tPretend run, print the commands without doing anything"
    echo -e "\t-r\tRuntime benchmark configuration, valid options are {base, c18n, c18n_ipc, revoke}"
    echo -e "\t-v\tBuild variant of the nginx server to run, this must match the package flavor"
    echo -e "\t-V\tEnable verbose diagnostics output"

    exit 1
}

# $1 => file
# $2 => data
function write_to()
{
    if [ -z "${X}" ]; then
        echo "${2}" > "${1}"
    else
        echo "==="
        echo "${2}"
        echo ">>> ${1}"
    fi
}

# Create self-signed certificate
function gen_ssl()
{
    # Generate a passphrase
    local secret=$(openssl rand -base64 48)
    write_to /tmp/passphrase.txt "${secret}"

    # Generate a Private Key
    ${X} openssl genrsa -aes128 -passout file:/tmp/passphrase.txt -out "${NGINX_ETC}/server.key" 2048

    # Generate a CSR (Certificate Signing Request)
    ${X} openssl req -new -passin file:/tmp/passphrase.txt \
         -key "${NGINX_ETC}/server.key" -out "${NGINX_ETC}/server.csr" \
         -subj "/C=UK/O=cheri/CN=*.cheri-nginx-benchmark.local"

    # Remove Passphrase from Key
    ${X} cp "${NGINX_ETC}/server.key" "${NGINX_ETC}/server.key.org"
    ${X} openssl rsa -in "${NGINX_ETC}/server.key.org" -passin file:/tmp/passphrase.txt \
         -out "${NGINX_ETC}/server.key"

    # Generating a Self-Signed Certificate for 1 year
    ${X} openssl x509 -req -days 365 -in "${NGINX_ETC}/server.csr" \
         -signkey "${NGINX_ETC}/server.key" -out "${NGINX_ETC}/server.crt"
}

function start_nginx()
{
    envcmd=""

    if [ "${NGINX_EXPERIMENT}" == "c18n_ipc" ]; then
       envcmd="env ${RTLD_ENV_PREFIX}COMPARTMENT_OVERHEAD=1"
    fi

    ${X} ${envcmd} ${NGINX_BINARY}
    if [ -z "${X}" ]; then
        if [ ! -f "${NGINX_PIDFILE}" ]; then
            echo "Failed to start nginx"
            exit 1
        fi
        echo "Nginx started at $(cat ${NGINX_PIDFILE})"
    fi
}

function stop_nginx()
{
    local nginx_pid

    # ${X} service nginx onestop
    if [ -z "${X}" ]; then
        if [ ! -f "${NGINX_PIDFILE}" ]; then
            echo "No nginx pidfile, crashed?"
            exit 1
        fi
        nginx_pid=$(cat ${NGINX_PIDFILE})
    else
        nginx_pid="<NGINX_PID>"
    fi

    ${X} kill -QUIT "${nginx_pid}"
    ${X} pwait "${nginx_pid}"
}

# $1 => iteration number
# $2 => scenario - the file to fetch with wrk
function run_wrk_one()
{
    local iteration=${1}
    local name=${2}
    local fullname="${name}"
    local wrk_args=""

    if [ -z "${PERSISTENT_WORKERS}" ]; then
        start_nginx
    fi
    if [ -n "${WRK_MSGLIMIT}" ]; then
        wrk_args="-s ${CURDIR}/wrk-msglimit-report.lua"
    else
        wrk_args="-d 1m -s ${CURDIR}/wrk-report.lua"
    fi
        wrk_script="wrk-report.lua"

    ${X} wrk -t 1 -c 50 ${wrk_args} "https://localhost:10443/rps/${fullname}"
    ${X} mv wrk-result.json "${NGINX_RESULTS_DIR}/result_${name}.${iteration}.json"

    if [ -z "${PERSISTENT_WORKERS}" ]; then
        stop_nginx
    fi
}

# $1 => scenario - the file to fetch with wrk
function run_wrk()
{
    local name=${1}
    echo "+++ Scenario ${name} ${NGINX_ITERATIONS} iterations +++"
    for i in $(seq 1 ${NGINX_ITERATIONS}); do
        run_wrk_one ${i} ${name}
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
            ;;
        a)
            NGINX_PACKAGE_ABI=${OPTARG}
            ;;
        r)
            NGINX_EXPERIMENT=${OPTARG}
            ;;
        f)
            WRK_MSGLIMIT=1
            ;;
        g)
            NGINX_SCENARIO_GROUP=${OPTARG}
            ;;
        i)
            NGINX_ITERATIONS=${OPTARG}
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
                NGINX_PACKAGE_FLAVOR="-${OPTARG}"
            fi
            ;;
        V)
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
        PKG=pkg64
        NGINX_CONF=/root/nginx/nginx64.conf
        C18N_INTERP=
        RTLD_ENV_PREFIX=
        ;;
    purecap)
        PREFIX=/usr/local
        PKG=pkg64c
        NGINX_CONF=/root/nginx/nginx.conf
        C18N_INTERP=ld-elf-c18n.so.1
        RTLD_ENV_PREFIX="LD_"
        ;;
    benchmark)
        PREFIX=/usr/local64cb
        PKG=pkg64cb
        NGINX_CONF=/root/nginx/nginx64cb.conf
        C18N_INTERP=ld-elf64cb-c18n.so.1
        RTLD_ENV_PREFIX="LD_64CB_"
        ;;
    *)
        echo "ERROR: invalid -a option, must be {hybrid, purecap, benchmark}"
        exit 1
esac

NGINX_PACKAGE="nginx${NGINX_PACKAGE_FLAVOR}-1.24.0_11,3.pkg"
NGINX_RESULTS_DIR="/root/results/grpc-${NGINX_PACKAGE_ABI}${NGINX_PACKAGE_FLAVOR:=-base}/${NGINX_EXPERIMENT}"

case "${NGINX_SCENARIO_GROUP}" in
    random)
        NGINX_SCENARIO_LIST=(random_0b random_512b random_1024b random_10240b random_102400b)
        ;;
    dasa)
        NGINX_SCENARIO_LIST=(random_1024b)
        ;;
    *)
        echo "Invalid scenario group selection"
        exit 1
esac


echo "NGINX_PACKAGE:      ${NGINX_PACKAGE}"
echo "NGINX_ITERATIONS:   ${NGINX_ITERATIONS}"
echo "NGINX_SCENARIOS:    ${NGINX_SCENARIO_LIST[@]}"
echo "NGINX_RESULTS_DIR:  ${NGINX_RESULTS_DIR}"
# Check whether runtime revocation is enabeld by default, we only want revocation explicitly
default_revoke=$(sysctl -n security.cheri.runtime_revocation_default)
echo "DEFAULT REVOKE:   ${default_revoke}"

if [ "$default_revoke" == "1" ]; then
    echo "ERROR: Runtime revocation is enabled by default, disable now"
    exit 1
fi

echo "=== Setup nginx packages ==="
if [ "${NGINX_PACKAGE_ABI}" == "hybrid" ]; then
    PKGDIR="/packages64"
else
    PKGDIR="/packages"
fi
${X} env ASSUME_ALWAYS_YES=yes ${PKG} add ${PKGDIR}/All/${NGINX_PACKAGE}
${X} env ASSUME_ALWAYS_YES=yes /usr/local64/sbin/pkg install wrk-luajit-openresty

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
        ${X} patchelf --set-interpreter "/libexec/${C18N_INTERP}" "${NGINX_BINARY}"
        ;;
    c18n_ipc)
        if [ -z "${C18N_INTERP}" ]; then
            echo "ERROR: can not use -r c18n with -a hybrid"
            exit 1
        fi
        echo "Patch nginx to enable c18n with overhead simulation"
        ${X} patchelf --set-interpreter "/libexec/overhead-${C18N_INTERP}" "${NGINX_BINARY}"
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
NGINX_WWW="${PREFIX}/www/nginx"
NGINX_ETC="${PREFIX}/etc/nginx"
${X} cp -r "/root/nginx/rps" "${NGINX_WWW}"
${X} cp "${NGINX_CONF}" "${NGINX_ETC}/nginx.conf"
${X} cp "${NGINX_ETC}/mime.types-dist" "${NGINX_ETC}/mime.types"
gen_ssl

if [ ! -z "${PERSISTENT_WORKERS}" ]; then
    start_nginx
fi

echo "=== Begin benchmark loop ==="
for scenario in ${NGINX_SCENARIO_LIST[@]}; do
    run_wrk ${scenario}
done
