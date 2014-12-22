#! /bin/sh
DPARSE=~/Documents/d_libs/libdparse

dmd -g \
    -I~${DPARSE}/src \
    ${DPARSE}/src/std/d/*.d \
    ${DPARSE}/src/std/*.d \
    test_runner.d \
    -oftest_runner
