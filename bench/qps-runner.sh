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
ROOTFS_DIR=
POUDRIERE_CONF=/usr/local/etc/poudriere.d
QPS_DEMO=$(readlink -f $(dirname "$0"))

OPTSTRING=":w:p:P:nx:r:c"
X=
STEP=
POUDRIERE_CLEAN=

ABIS=(hybrid purecap benchmark)
#VARIANTS=(base stackinit)
VARIANTS=(base)
RUNTIMES=(base c18n revoke)

function usage()
{
    echo "$0 - Setup the jails and build packages for the Morello gRPC qps benchmark"
    echo "Options":
    echo -e "\t-h\tShow help message"
    echo -e "\t-w\tWorkspace where results are stored, default ${WORKSPACE}"
    echo -e "\t-r\tPath to the directory containing rootfs for the jails, default ${WORKSPACE}"
    echo -e "\t-p\tPorts tree name, default ${PORTS_NAME}"
    echo -e "\t-P\tPath to the ports tree, default ${PORTS_PATH}"
    echo -e "\t-n\tPretend run, print the commands without doing anything"
    echo -e "\t-x\tExecute given step, valid values are {setup, qps}"
    echo -e "\t-c\tClean the grpc-qps package in jails build but not dependencies"
    exit 1
}

while getopts ${OPTSTRING} opt; do
    case ${opt} in
        w)
            WORKSPACE=${OPTARG}
            if [ -z "${ROOTFS_DIR}" ]; then
                ROOTFS_DIR=${WORKSPACE}
            fi
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
        r)
            ROOTFS_DIR=${OPTARG}
            ;;
        n)
            X="echo"
            ;;
        x)
            STEP=${OPTARG}
            ;;
        c)
            POUDRIERE_CLEAN="-C"
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

# Generate jail name
# $1 => abi
# $2 => variant
# $3 => runtime
function jailname()
{
    echo "${JAIL_PREFIX}${1}-${2}"
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
            mount="${ROOTFS_DIR}/rootfs-morello-hybrid"
            ;;
        purecap|benchmark)
            arch="arm64.aarch64c"
            mount="${ROOTFS_DIR}/rootfs-morello-purecap"
            ;;
        *)
            echo "Invalid ABI conf ${1}"
            exit 1
            ;;
    esac

    name="$(jailname ${1} ${2} ${3})"
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
function buildpkg()
{
    port_set=$(abi_to_port_set ${1})
    if [ "${2}" = "stackinit" ]; then
        port_set="${port_set}_stackzero"
    fi
    name="$(jailname ${1} ${2} ${3})"
    ${X} poudriere bulk -j "${name}" -p "${PORTS_NAME}" -z "${port_set}" \
         "${POUDRIERE_CLEAN}" benchmarks/grpc-qps
}

# $1 => jail abi
# $2 => jail variant
# $3 => jail runtime configuration
# Generate the benchmark result directories. These are used by the jail hook script to
# mount the correct output directory at /root/results in the jail
function ensure_result_dirs()
{
    abi=${1}
    variant=${2}
    rt=${3}

    name="${JAIL_PREFIX}${abi}-${variant}"
    ${X} mkdir -p "${WORKSPACE}/results/${name}/${rt}"
}

# Determine whether the tuple (abi, variant, runtime) is valid
# $1 => jail abi
# $2 => jail variant
# $3 => jail runtime config
function valid_combination()
{
    abi=${1}
    variant=${2}
    rt=${3}

    if [ "${abi}" == "hybrid" ] && ([ "${variant}" != "base" ] || [ "${rt}" != "base" ]); then
        return 0
    else
        return 1
    fi
}

# Main setup function
# This creates jails and builds packages
function setup()
{
    # Create the ports tree
    mkports "${PORTS_NAME}" "${PORTS_PATH}"

    # Create build jails if not existing
    echo "Create jails"

    for abi in ${ABIS[@]}; do
        for variant in ${VARIANTS[@]}; do
            mkjail ${abi} ${variant}
        done
    done

    # Build packages for each target / feature combination
    echo "Start building packages"
    for abi in ${ABIS[@]}; do
        for variant in ${VARIANTS[@]}; do
            buildpkg ${abi} ${variant}
        done
    done

    # Ensure that the result directories exist
    ${X} mkdir -p ${WORKSPACE}/results
    for abi in ${ABIS[@]}; do
        for variant in ${VARIANTS[@]}; do
            for rt in ${RUNTIMES[@]}; do
                if valid_combination ${abi} ${variant} ${rt}; then
                    continue
                fi
                ensure_result_dirs ${abi} ${variant} ${rt}
            done
        done
    done

    # Install the poudriere jail hook to mount
    # ${WORKSPACE}/results into root/results
    # ${WORKSPACE}/qps into root/scripts
    jail_hook="$(m4 -DQPS_WORKSPACE=${WORKSPACE} -DQPS_SCRIPTS=${QPS_DEMO}/qps ${QPS_DEMO}/jail-hook.sh.in)"

    write_to ${POUDRIERE_CONF}/hooks/jail.sh "${jail_hook}"
}

# Run the QPS benchmark in a jail
# $1 => abi
# $2 => variant
# $3 => runtime config
function run_qps_jail()
{
    abi="${1}"
    variant="${2}"
    rt="${3}"

    echo "+++ Run benchmark for ${abi} variant=${variant} runtime=${rt} +++"

    name=$(jailname ${abi} ${variant} ${rt})
    port_set=$(abi_to_port_set ${abi})
    echo "Run QPS in jail ${name}"
    ${X} poudriere jail -s -j "${name}" -p "${PORTS_NAME}" -z "${port_set}"
    # Note that the -n suffix indicates the jail instance with network access
    jail_fullname="${name}-${PORTS_NAME}-${port_set}-n"
    ${X} jexec "${jail_fullname}" /bin/csh -c "/root/qps/bootstrap.sh"
    ${X} jexec "${jail_fullname}" /bin/csh -c "/root/qps/run-qps.sh -a ${abi} -r ${rt}"
    ${X} poudriere jail -k -j "${name}" -p "${PORTS_NAME}" -z "${port_set}"
}

# Run the QPS benchmark across all jails
function run_qps()
{
    revoke_ctl=$(sysctl -n security.cheri.runtime_revocation_default)
    if [ "${revoke_ctl}" == "1" ]; then
        echo "Default revocation is enabled, switch it off for the benchmark"
        ${X} sysctl security.cheri.runtime_revocation_default=0
    fi

    if [ -z "${QPS_SKIP_KERNEL_CHECK}" ]; then
        nodebug=$(uname -a | grep NODEBUG)
        if [ -z "${nodebug}" ]; then
            echo "WARNING: Refusing to run on non-benchmark kernel, set the QPS_SKIP_KERNEL_CHECK env var to override"
            exit 1
        fi
    fi

    echo "Run QPS benchmarks"
    for abi in ${ABIS[@]}; do
        for variant in ${VARIANTS[@]}; do
            for rt in ${RUNTIMES[@]}; do
                if valid_combination ${abi} ${variant} ${rt}; then
                    continue
                fi
                run_qps_jail ${abi} ${variant} ${rt}
            done
        done
    done
}

if [ "$STEP" == "setup" ]; then
    setup
elif [ "$STEP" == "qps" ]; then
    run_qps
elif [ -z "$STEP" ]; then
    echo "Missing command, use -x option"
    exit 1
else
    echo "Invalid command '$STEP'"
    exit 1
fi
