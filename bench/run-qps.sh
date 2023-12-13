#!/bin/bash
#
# This script runs the qps benchmark and collects results within a jail
#
#

JAIL_PREFIX="grpc-"
PORTS_NAME=grpc-qps-ports
WORKSPACE=${PWD}

OPTSTRING=":w:p:n"
X=

function usage()
{
    echo "$0 - Setup the jails and build packages for the Morello gRPC qps benchmark"
    echo "Options":
    echo -e "\t-h\tShow help message"
    echo -e "\t-w\tWorkspace where the jail rootfs can be found, default ${WORKSPACE}"
    echo -e "\t-p\tPorts tree name, default ${PORTS_NAME}"
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

${X} mkdir -p ${WORKSPACE}/results

# $1 => jail abi
# $2 => jail variant
# $3 => jail runtime configuration
function run_qps()
{
    case ${1} in
        hybrid)
            mount="${WORKSPACE}/rootfs-morello-hybrid"
            ;;
        purecap|benchmark)
            mount="${WORKSPACE}/rootfs-morello-purecap"
            ;;
        *)
            echo "Invalid ABI conf ${1}"
            exit 1
            ;;
    esac

    ${X} mkdir -p ${mount}/root/results
    ${X} mount_nullfs ${WORKSPACE}/results ${mount}/root/results

    name="${JAIL_PREFIX}${1}-${2}"
    if [ "$(poudriere jail -q -l | grep ${name})" = "" ]; then
        echo "Create jail ${name}"
        ${X} poudriere jail -c -j "${name}" -a ${arch} -o CheriBSD -v dev -m null -M "${mount}"
    else
        echo "Jail ${name} exists, skip"
    fi
}
