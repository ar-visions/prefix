#!/bin/bash
mkdir -p ion-build
cd ion-build
cmake -G "MinGW Makefiles" . "$@"
