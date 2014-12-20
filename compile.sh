#! /bin/sh
DPARSE=~/Documents/d_libs/libdparse

dmd -g \
    -I~/.dub/packages/yajl-0.2.0/src/ \
    ~/.dub/packages/yajl-0.2.0/src/**/*.d \
    -I~${DPARSE}/src \
    ${DPARSE}/src/std/d/*.d \
    ${DPARSE}/src/std/*.d \
    source/unknown.d \
    source/main.d \
    source/configuration.d \
    source/cli.d \
    source/dlang_decls.d \
    source/translate.d \
    source/dlang_output.d \
    source/binder.d \
    source/manual_types.d \
    -L-Lbuild \
    -L-lcpp_binder \
    -L-lyajl \
    -L-lclangTooling \
    -L-lclangDriver \
    -L-lclangFrontend \
    -L-lclangParse \
    -L-lclangSema \
    -L-lclangEdit \
    -L-lclangAnalysis \
    -L-lclangAST \
    -L-lclangLex \
    -L-lclangSerialization \
    -L-lclangBasic \
    -L-lclang \
    -L-lLLVM-3.5 \
    -L-lboost_filesystem \
    -L-lboost_system \
    -L-lstdc++ \
    -ofbuild/cpp_binder
