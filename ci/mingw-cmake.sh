#!/bin/bash
# make build directory if it doesnt exist
mkdir -p ion-build
cmake "$@"
