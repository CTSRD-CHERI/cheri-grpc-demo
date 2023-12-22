#!/bin/bash
#
# This script produces qps and nginx benchmark packages using poudriere.
#

JAIL_PREFIX="grpc-"
PORTS_NAME=dasanext
PORTS_PATH=${HOME}/cheri/cheribsd-ports-next
WORKSPACE=${PWD}
ROOTFS_DIR=
POUDRIERE_CONF=/usr/local/etc/poudriere.d
QPS_DEMO=$(readlink -f $(dirname "$0"))

OPTSTRING=":w:p:P:nx:R:cCi:g:a:v:r:"
X=
STEP=
POUDRIERE_CLEAN=

ABIS=(hybrid purecap benchmark)
VARIANTS=(base stackzero subobj)
RUNTIMES=(base c18n revoke)
ITERATIONS=
SCENARIO_GROUP=

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
    echo -e "\t-x\tExecute given step, valid values are {setup, qps-packages, " \
         "nginx-packages, qps, nginx}"
    echo -e "\t-c\tClean the grpc-qps package in jails build but not dependencies"
    echo -e "\t-C\tClean all the packages when building"
    echo -e "\t-i\tBenchmark iterations to run (default see qps/run-qps.sh)"
    echo -e "\t-g\tQPS scenario group (default see qps/run-qps.sh)"
    echo -e "\t-a\tOverride the target ABI (hybrid, purecap, benchmark)"
    echo -e "\t-v\tOverride the compilation mode variant (base, stackzero, subobj)"
    echo -e "\t-r\tOverride the run-time configuration (base, c18n, revoke)"
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
        R)
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
        C)
            POUDRIERE_CLEAN="-c"
            ;;
        i)
            ITERATIONS=${OPTARG}
            ;;
        g)
            SCENARIO_GROUP=${OPTARG}
            ;;
        a)
            if [[ ${ABIS[@]} =~ ${OPTARG} ]]; then
                ABIS=(${OPTARG})
            else
                echo "Invalid -a option, must be one of ${ABIS[@]}"
                usage
            fi
            ;;
        v)
            if [[ ${VARIANTS[@]} =~ ${OPTARG} ]]; then
                VARIANTS=(${OPTARG})
            else
                echo "Invalid -v option, must be one of ${VARIANTS[@]}"
                usage
            fi
            ;;
        r)
            if [[ ${RUNTIMES[@]} =~ ${OPTARG} ]]; then
                RUNTIMES=(${OPTARG})
            else
                echo "Invalid -r option, must be one of ${RUNTIMES[@]}"
                usage
            fi
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

# $1 => package name
# $2 => jail abi
# $3 => jail variant
# $4 => jail runtime configuration
function buildpkg()
{
    package=${1}
    abi=${2}
    variant=${3}
    rt=${4}

    port_set=$(abi_to_port_set ${abi})
    if [ "${variant}" == "stackzero" ]; then
        package="${package}@stackzero"
    elif [ "${variant}" == "subobj" ]; then
        package="${package}@subobj"
    fi
    name="$(jailname ${abi} ${variant} ${rt})"
    ${X} poudriere bulk -j "${name}" -p "${PORTS_NAME}" -z "${port_set}" \
         ${POUDRIERE_CLEAN} "${package}"
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
# $1 => benchmark type (qps, nginx)
# $2 => jail abi
# $3 => jail variant
# $4 => jail runtime config
# Note, we need to return exit code 1 when the combination is NOT valid
function valid_combination()
{
    bench=${1}
    abi=${2}
    variant=${3}
    rt=${4}

    # Hybrid can only run the baseline tuple
    if [ "${abi}" == "hybrid" ] && ([ "${variant}" != "base" ] || [ "${rt}" != "base" ]); then
        return 1
    fi

    # TODO implement stackzero
    if [ "${variant}" == "stackzero" ]; then
        return 1
    fi

    case ${bench} in
        qps)
            # QPS does not support subobject
            if [ "${variant}" == "subobj" ]; then
                return 1
            fi
            ;;
        nginx)
            # Everything else is allowed
            ;;
        *)
            echo "Invalid target for valid_combination ${bench}"
            exit 1
    esac

    return 0
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

    # Install the poudriere jail hook to mount
    # ${WORKSPACE}/results into root/results
    # ${WORKSPACE}/qps into root/qps
    # ${WORKSPACE}/nginx into root/nginx
    jail_hook="$(m4 -DQPS_WORKSPACE=${WORKSPACE} -DQPS_SCRIPTS=${QPS_DEMO}/qps -DNGINX_SCRIPTS=${QPS_DEMO}/nginx ${QPS_DEMO}/jail-hook.sh.in)"

    write_to ${POUDRIERE_CONF}/hooks/jail.sh "${jail_hook}"
}

# Build qps packages for each jail
function build_qps()
{
    # Build packages for each target / feature combination
    echo "Building qps packages"
    for abi in ${ABIS[@]}; do
        for variant in ${VARIANTS[@]}; do
            if valid_combination "qps" ${abi} ${variant} "base"; then
                buildpkg "benchmarks/grpc-qps" ${abi} ${variant}
            fi
        done
    done
}

# Build nginx packages for each jail
function build_nginx()
{
    # Build packages for each target / feature combination
    echo "Building nginx packages"
    for abi in ${ABIS[@]}; do
        for variant in ${VARIANTS[@]}; do
            if valid_combination "nginx" ${abi} ${variant} "base"; then
                buildpkg "www/nginx" ${abi} ${variant}
            fi
        done
    done
}

# Run the wrk benchmark for nginx in a jail
# $1 => abi
# $2 => variant
# $3 => runtime config
# $4 => benchmark (qps, nginx)
function run_jail()
{
    abi="${1}"
    variant="${2}"
    rt="${3}"
    bench="${4}"

    echo "+++ Run ${bench} benchmark for ${abi} variant=${variant} runtime=${rt} +++"

    bootstrap_script="/root/${bench}/bootstrap.sh ${abi}"
    exec_script="/root/${bench}/run.sh -a ${abi} -r ${rt}"

    name=$(jailname ${abi} ${variant} ${rt})
    port_set=$(abi_to_port_set ${abi})
    ${X} poudriere jail -s -j "${name}" -p "${PORTS_NAME}" -z "${port_set}"
    # Note that the -n suffix indicates the jail instance with network access
    jail_execname="${name}-${PORTS_NAME}-${port_set}-n"
    ${X} jexec "${jail_execname}" /bin/csh -c "${bootstrap_script}"
    if [ $? != 0 ]; then
        echo "Could not bootstrap ${bench}"
        exit 1
    fi
    extra_args=
    if [ ! -z "${ITERATIONS}" ]; then
        extra_args+=" -i ${ITERATIONS}"
    fi
    if [ ! -z "${SCENARIO_GROUP}" ]; then
        extra_args+=" -g ${SCENARIO_GROUP}"
    fi
    ${X} jexec "${jail_execname}" /bin/csh -c "${exec_script} ${extra_args}"
    ${X} poudriere jail -k -j "${name}" -p "${PORTS_NAME}" -z "${port_set}"
}

# Run the benchmark across all jails
# $1 => benchmark name (qps, nginx)
function run_benchmark()
{
    bench="${1}"

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

    # Note that some gRPC tests can spawn a lot of threads
    # Increment the thread per proc limit
    thr_limit=$(sysctl -n kern.threads.max_threads_per_proc)
    if (( ${thr_limit} < 5000 )); then
        echo "WARNING: Detected low max_threads_per_proc limit, increasing to 5k"
        ${X} sysctl kern.threads.max_threads_per_proc=5000
    fi

    # Ensure that the result directories exist
    ${X} mkdir -p ${WORKSPACE}/results
    for abi in ${ABIS[@]}; do
        for variant in ${VARIANTS[@]}; do
            for rt in ${RUNTIMES[@]}; do
                if valid_combination ${bench} ${abi} ${variant} ${rt}; then
                    continue
                fi
                ensure_result_dirs ${abi} ${variant} ${rt}
            done
        done
    done

    echo "Run ${bench} benchmarks"
    for abi in ${ABIS[@]}; do
        for variant in ${VARIANTS[@]}; do
            for rt in ${RUNTIMES[@]}; do
                if valid_combination ${bench} ${abi} ${variant} ${rt}; then
                    continue
                fi

                run_jail ${abi} ${variant} ${rt} ${bench}
            done
        done
    done
}

if [ "$STEP" == "setup" ]; then
    setup
elif [ "$STEP" == "qps-packages" ]; then
    build_qps
elif [ "$STEP" == "qps" ]; then
    run_benchmark qps
elif [ "$STEP" == "nginx-packages" ]; then
    build_nginx
elif [ "$STEP" == "nginx" ]; then
    run_benchmark nginx
elif [ -z "$STEP" ]; then
    echo "Missing command, use -x option"
    exit 1
else
    echo "Invalid command '$STEP'"
    exit 1
fi
