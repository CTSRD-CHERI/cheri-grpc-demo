#!/bin/sh

set -e

env ASSUME_ALWAYS_YES=yes pkg64 install bash python py39-six patchelf

echo "PYTHON $(python --version)"
echo "BASH $(bash --version)"
