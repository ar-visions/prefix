#!/bin/bash
mkdir -p ion-build
cd ion-build
cmake --install . "$@"
