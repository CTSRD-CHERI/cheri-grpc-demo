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
CURDIR=$(readlink -f $(dirname "$0"))

OPTSTRING=":w:p:P:nx:R:cCi:f:g:a:v:r:j:J:Vo:"
X=
STEP=
POUDRIERE_CLEAN=

ABIS=(hybrid purecap benchmark)
VARIANTS=(base stackzero subobj)
RUNTIMES=(base c18n c18n_policy c18n_ipc revoke)
ITERATIONS=
SCENARIO_GROUP=
FIXED_WORKLOAD=
HWPMC_SAMPLING=
HWPMC_COUNTING=
DEBUG_MODE=
OUTPUT_DIR="results"

HELP_ABIS="${ABIS[@]}"
HELP_ABIS="${HELP_ABIS// /, }"
HELP_VARIANTS="${VARIANTS[@]}"
HELP_VARIANTS="${HELP_VARIANTS// /, }"
HELP_RT="${RUNTIMES[@]}"
HELP_RT="${HELP_RT// /, }"

function usage()
{
    echo "$0 - Setup the jails and build packages for the Morello gRPC qps benchmark"
    echo "Options":
    echo -e "\t-a\tOverride the target ABI (${HELP_ABIS})"
    echo -e "\t-c\tClean the target package in jails build but not dependencies"
    echo -e "\t-C\tClean all the packages when building"
    echo -e "\t-f\tUse a fixed-size workload instead of fixed-time, speciy the suffix for the scenario file"
    echo -e "\t-g\tQPS scenario group (default see qps/run.sh)"
    echo -e "\t-h\tShow help message"
    echo -e "\t-i\tBenchmark iterations to run (default see qps/run.sh)"
    echo -e "\t-j\tEnable hwpmc profiling in sampling mode every <arg> instructions"
    echo -e "\t-J\tEnable hwpmc counters in the given group (inst, cheri)"
    echo -e "\t-n\tPretend run, print the commands without doing anything"
    echo -e "\t-o\tName of the result directory, defaults to results"
    echo -e "\t-p\tPorts tree name, default ${PORTS_NAME}"
    echo -e "\t-P\tPath to the ports tree, default ${PORTS_PATH}"
    echo -e "\t-r\tOverride the run-time configuration (${HELP_RT})"
    echo -e "\t-R\tPath to the directory containing rootfs for the jails, default ${WORKSPACE}"
    echo -e "\t-v\tOverride the compilation mode variant (${HELP_VARIANTS})"
    echo -e "\t-V\tEnable verbose diagnostics"
    echo -e "\t-w\tWorkspace where results are stored, default ${WORKSPACE}"
    echo -e "\t-x\tExecute given step, valid values are {setup, clean, qps-packages, " \
         "nginx-packages, qps, nginx}"

    exit 1
}

args=`getopt ${OPTSTRING} $*`
if [ $? -ne 0 ]; then
    usage
fi
set -- $args

while :; do
    option="$1"
    shift
    optvalue="$1"
    case "${option}" in
        -a)
            if [[ ${ABIS[@]} =~ ${optvalue} ]]; then
                ABIS=(${optvalue})
            else
                echo "Invalid -a option, must be one of ${ABIS[@]}"
                usage
            fi
            shift
            ;;
        -c)
            POUDRIERE_CLEAN="-C"
            ;;
        -C)
            POUDRIERE_CLEAN="-c"
            ;;
        -f)
            FIXED_WORKLOAD=${optvalue}
            ;;
        -g)
            SCENARIO_GROUP=${optvalue}
            shift
            ;;
        -h)
            usage
            ;;
        -i)
            ITERATIONS=${optvalue}
            shift
            ;;
        -j)
            HWPMC_SAMPLING=${optvalue}
            shift
            ;;
        -J)
            HWPMC_COUNTING=${optvalue}
            shift
            ;;
        -n)
            X="echo"
            ;;
        -o)
            OUTPUT_DIR=${optvalue}
            ;;
        -p)
            PORTS_NAME=${optvalue}
            shift
            ;;
        -P)
            PORTS_PATH=${optvalue}
            shift
            ;;
        -r)
            if [[ ${RUNTIMES[@]} =~ ${optvalue} ]]; then
                RUNTIMES=(${optvalue})
            else
                echo "Invalid -r option, must be one of ${RUNTIMES[@]}"
                usage
            fi
            shift
            ;;
        -R)
            ROOTFS_DIR=${optvalue}
            shift
            ;;
        -v)
            if [[ ${VARIANTS[@]} =~ ${optvalue} ]]; then
                VARIANTS=(${optvalue})
            else
                echo "Invalid -v option, must be one of ${VARIANTS[@]}"
                usage
            fi
            shift
            ;;
        -V)
            DEBUG_MODE=1
            ;;
        -w)
            WORKSPACE=${optvalue}
            if [ -z "${ROOTFS_DIR}" ]; then
                ROOTFS_DIR=${WORKSPACE}
            fi
            shift
            ;;
        -x)
            STEP=${optvalue}
            shift
            ;;
        --)
            break
            ;;
    esac
done

# while getopts ${OPTSTRING} opt; do
# done

echo "$0 configuration:"
echo "WORKSPACE=${WORKSPACE}"
echo "PORTS_NAME=${PORTS_NAME}"
echo "PORTS_PATH=${PORTS_PATH}"

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

# Get the poudriere port setname for a given abi
# $1 => abi name (hybridabi, cheriabi, benchmarkabi)
# $2 => "run" if we are running the jail, "build" if we are building packages
function abi_to_port_set()
{
    local run_or_build=${2}

    case ${1} in
        hybrid)
            if [ "${run_or_build}" = "run" ]; then
                port_set="cheriabi"
            else
                port_set="hybridabi"
            fi
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

# Generate a list of hwpmc names for pmcstat given a group name
# $1 => counter group
function hwpmc_counters()
{
    local group=${1}

    case ${group} in
        inst)
            echo "CPU_CYCLES,INST_RETIRED,INST_SPEC,EXECUTIVE_ENTRY,EXECUTIVE_EXIT,INST_SPEC_RESTRICTED"
            ;;
        l1cache)
            echo "CPU_CYCLES,INST_RETIRED,L1D_CACHE_REFILL,L1D_CACHE,L1D_CACHE_WB_VICTIM,L1I_CACHE,L1I_TLB_REFILL,L1I_CACHE_REFILL,L1D_TLB_REFILL"
            ;;
        l2cache)
            echo "CPU_CYCLES,INST_RETIRED,L2D_CACHE_REFILL,L2D_CACHE,L2D_CACHE_WB_VICTIM,BUS_ACCESS"
            ;;
        branch)
            echo "CPU_CYCLES,INST_RETIRED,BR_MIS_PRED,BR_PRED,BR_MIS_PRED_RS,BR_RETIRED,BR_MIS_PRED_RETIRED,BR_RETURN_SPEC"
            ;;
        *)
            # Override hwpmc counter group, use ${group}
            echo "${group}"
            ;;
    esac
}

# Generate jail name for benchmarking
# Note that we use the purecap jail for hybrid runs as well
# this addresses a limitation of pmcstat.
# $1 => "run" or "build"
# $2 => abi
# $3 => variant
# $4 => runtime
function jailname()
{
    local run_or_build=${1}
    local abi=${2}
    local variant=${3}

    if [ "${run_or_build}" = "build" ]; then
        echo "${JAIL_PREFIX}${abi}-${variant}"
    else
        if [ "${abi}" = "hybrid" ]; then
            abi="purecap"
        fi
        echo "${JAIL_PREFIX}${abi}-${variant}"
    fi
}

# Wipe all jails we created
function wipe()
{
    for abi in ${ABIS[@]}; do
        for variant in ${VARIANTS[@]}; do
            name=`jailname build ${abi} ${variant}`
            echo "Drop jail ${name}"
            ${X} poudriere jail -d -j "${name}"
        done
    done
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
    local abi=${1}
    local variant=${2}
    local rt=${3}

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

    name="$(jailname build ${abi} ${variant} ${rt})"
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

    port_set=$(abi_to_port_set ${abi} "build")
    if [ "${variant}" == "stackzero" ]; then
        package="${package}@stackzero"
    elif [ "${variant}" == "subobj" ]; then
        package="${package}@subobj"
    fi
    name="$(jailname build ${abi} ${variant} ${rt})"
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
            if [ "${rt}" == "c18n_policy" ]; then
                # We have no policy for wrk
                return 1
            fi

            # if [ "${rt}" == "revoke" ]; then
            #     # XXX Temporarily disable revoke as it seems to trigger kernel panic
            #     return 1
            # fi
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

    local hybrid_jail_name=`jailname build hybrid base base`

    # Install the poudriere jail hook to mount
    # ${WORKSPACE}/results into root/results
    # ${WORKSPACE}/qps into root/qps
    # ${WORKSPACE}/nginx into root/nginx
    jail_hook="$(m4 -D__QPS_WORKSPACE=${WORKSPACE} -D__QPS_SCRIPTS=${CURDIR}/qps -D__NGINX_SCRIPTS=${CURDIR}/nginx -D__HYBRID_JAIL_NAME=${hybrid_jail_name} ${CURDIR}/jail-hook.sh.in)"

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
    exec_script="/root/${bench}/run.sh -a ${abi} -v ${variant} -r ${rt}"

    name=$(jailname run ${abi} ${variant} ${rt})
    port_set=$(abi_to_port_set ${abi} "run")
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
    if [ -n "${FIXED_WORKLOAD}" ]; then
        extra_args+=" -f ${FIXED_WORKLOAD}"
    fi
    if [ -n "${HWPMC_SAMPLING}" ]; then
        extra_args+=" -j ${HWPMC_SAMPLING}"
    fi
    if [ -n "${HWPMC_COUNTING}" ]; then
        local counters=`hwpmc_counters ${HWPMC_COUNTING}`
        extra_args+=" -J ${counters}"
    fi
    if [ -n "${DEBUG_MODE}" ]; then
        extra_args+=" -V"
    fi
    ${X} jexec "${jail_execname}" /bin/csh -c "${exec_script} ${extra_args}"
    ${X} poudriere jail -k -j "${name}" -p "${PORTS_NAME}" -z "${port_set}"
}

# Run the benchmark across all jails
# $1 => benchmark name (qps, nginx)
function run_benchmark()
{
    local bench="${1}"

    local revoke_ctl=$(sysctl -n security.cheri.runtime_revocation_default)
    if [ "${revoke_ctl}" == "1" ]; then
        echo "Default revocation is enabled, switch it off for the benchmark"
        ${X} sysctl security.cheri.runtime_revocation_default=0
    fi

    if [ -n "${HWPMC_SAMPLING}" ] || [ -n "${HWPMC_COUNTING}" ]; then
        local has_hwpmc=`kldstat | grep hwpmc`
        if [ -z "${has_hwpmc}" ]; then
            echo "Missing hwpmc kernel module, try to load"
            ${X} kldload hwpmc
        fi
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
    local thr_limit=$(sysctl -n kern.threads.max_threads_per_proc)
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
                    ensure_result_dirs ${abi} ${variant} ${rt}
                fi
            done
        done
    done

    echo "Run ${bench} benchmarks"
    for abi in ${ABIS[@]}; do
        for variant in ${VARIANTS[@]}; do
            for rt in ${RUNTIMES[@]}; do
                if valid_combination ${bench} ${abi} ${variant} ${rt}; then
                    run_jail ${abi} ${variant} ${rt} ${bench}
                fi
            done
        done
    done
}

if [ "$STEP" == "setup" ]; then
    setup
elif [ "$STEP" == "clean" ]; then
    wipe
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
