#!/bin/sh

echo "Bootstrap QPS benchmark dependencies for ${1}"
echo "Check whether we have pkg"
if [ "$1" == "hybrid" ]; then
    # env ASSUME_ALWAYS_YES=yes pkg
    # cp -r /etc/pkg /etc/pkg64
    # PKG=/usr/local64/sbin/pkg
    PKG=pkg64
elif [ "$1" == "purecap" ]; then
    PKG=pkg64c
elif [ "$1" == "benchmark" ]; then
    PKG=pkg64cb
else
    echo "Invalid ABI argument"
    exit 1
fi

if ! test -f "$(which ${PKG})"; then
    echo "Could not find pkg at ${PKG}"
    exit 1
fi

env ASSUME_ALWAYS_YES=yes /usr/local64/sbin/pkg install bash python py39-six patchelf

echo "PYTHON $(python --version)"
echo "BASH $(bash --version)"
