#!/bin/bash
#
# This script produces grpc benchmark packages using poudriere.
# Note that this requires a specific poudriere branch with patches to enable building
# package variations with LLVM stack zeroing.
#

JAIL_PREFIX="grpc-"
PORTS_NAME=dasanext
PORTS_PATH=${HOME}/cheri/cheribsd-ports-next
WORKSPACE=${PWD}
POUDRIERE_CONF=/usr/local/etc/poudriere.d
QPS_DEMO=$(dirname "$0")

OPTSTRING=":w:p:P:n"
X=

function usage()
{
    echo "$0 - Setup the jails and build packages for the Morello gRPC qps benchmark"
    echo "Options":
    echo -e "\t-h\tShow help message"
    echo -e "\t-w\tWorkspace where the jail rootfs can be found, default ${WORKSPACE}"
    echo -e "\t-p\tPorts tree name, default ${PORTS_NAME}"
    echo -e "\t-P\tPath to the ports tree, default ${PORTS_PATH}"
    echo -e "\t-n\tPretend run, print the commands without doing anything"
    exit 1
}

while getopts ${OPTSTRING} opt; do
    case ${opt} in
        w)
            WORKSPACE=${OPTARG}
            ;;
        h)
            usage
            ;;
        p)
            PORTS_NAME=${OPTARG}
            ;;
        P)
            PORTS_PATH=${OPTARG}
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

echo "$0 configuration:"
echo "WORKSPACE=${WORKSPACE}"
echo "PORTS_NAME=${PORTS_NAME}"
echo "PORTS_PATH=${PORTS_PATH}"

# $1 => file
# $2 => data
function write_to()
{
    if [ "${X}" = "" ]; then
        echo "${2}" > "${1}"
    else
        echo "==="
        echo "${2}"
        echo ">>> ${1}"
    fi
}

# Get the poudriere port setname for a given abi
# $1 => abi name (hybridabi, cheriabi, benchmarkabi)
function abi_to_port_set()
{
    case ${1} in
        hybrid)
            port_set="hybridabi"
            ;;
        purecap)
            port_set="cheriabi"
            ;;
        benchmark)
            port_set="benchmarkabi"
            ;;
        *)
            echo "Invalid ABI conf ${1}"
            exit 1
    esac
    echo ${port_set}
}

# Wipe all jails we created as well as the ports tree
function wipe()
{
    echo "TODO"
}

# $1 => tree name
# $2 => tree path
function mkports()
{
    if [ "$(poudriere ports -q -l | grep ${1})" = "" ]; then
        echo "Create ports tree ${1}"
        ${X} poudriere ports -c -f none -m null -M "${2}" -p "${1}"
    fi
}

# $1 => jail abi
# $2 => jail variant
# $3 => jail runtime configuration
function mkjail()
{
    case ${1} in
        hybrid)
            arch="arm64.aarch64"
            mount="${WORKSPACE}/rootfs-morello-hybrid"
            ;;
        purecap|benchmark)
            arch="arm64.aarch64c"
            mount="${WORKSPACE}/rootfs-morello-purecap"
            ;;
        *)
            echo "Invalid ABI conf ${1}"
            exit 1
            ;;
    esac


    name="${JAIL_PREFIX}${1}-${2}"
    if [ "$(poudriere jail -q -l | grep ${name})" = "" ]; then
        echo "Create jail ${name}"
        ${X} poudriere jail -c -j "${name}" -a ${arch} -o CheriBSD -v dev -m null -M "${mount}"
    else
        echo "Jail ${name} exists, skip"
    fi
}

# $1 => jail abi
# $2 => jail variant
# $3 => jail runtime configuration
function buildjail()
{
    port_set=$(abi_to_port_set ${1})
    if [ "${2}" = "stackinit" ]; then
        port_set="${port_set}_stackzero"
    fi
    name="${JAIL_PREFIX}${1}-${2}"
    ${X} poudriere bulk -j "${name}" -p "${PORTS_NAME}" -z "${port_set}" benchmarks/grpc-qps
}

# $1 => jail abi
# $2 => jail variant
# $3 => jail runtime configuration
# Generate the benchmark result directories. These are used by the jail hook script to
# mount the correct output directory at /root/results in the jail
function ensure_result_dirs()
{
    ${X} mkdir -p "${WORKSPACE}/results/${JAIL_PREFIX}${1}-${2}-${3}"
}

# Create the ports tree
mkports "${PORTS_NAME}" "${PORTS_PATH}"

# Create build jails if not existing
echo "Create jails"
ABIS=(hybrid purecap benchmark)
#VARIANTS=(base stackinit)
VARIANTS=(base)
RUNTIMES=(base c18n revoke)

for abi in ${ABIS[@]}; do
    for variant in ${VARIANTS[@]}; do
        mkjail ${abi} ${variant}
    done
done

# Build packages for each target / feature combination
echo "Start building packages"
for abi in ${ABIS[@]}; do
    for variant in ${VARIANTS[@]}; do
        buildjail ${abi} ${variant}
    done
done

# Ensure that the result directories exist
${X} mkdir -p ${WORKSPACE}/results
for abi in ${ABIS[@]}; do
    for variant in ${VARIANTS[@]}; do
        for rt in ${RUNTIMES[@]}; do
            ensure_result_dirs ${abi} ${variant} ${rt}
        done
    done
done

# Install the poudriere jail hook to mount
# ${WORKSPACE}/results into root/results
# ${WORKSPACE}/qps into root/scripts
jail_hook="$(m4 -DQPS_WORKSPACE=${WORKSPACE} -DQPS_SCRIPTS=${QPS_DEMO}/qps ${QPS_DEMO}/jail-hook.sh.in)"

write_to ${POUDRIERE_CONF}/hooks/jail.sh "${jail_hook}"

