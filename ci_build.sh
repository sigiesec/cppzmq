#!/usr/bin/env bash

set -x
set -e

BUILD_TYPE=${BUILD_TYPE:-cmake}
ZMQ_VERSION=${ZMQ_VERSION:-4.2.5}
ENABLE_DRAFTS=${ENABLE_DRAFTS:-OFF}
COVERAGE=${COVERAGE:-OFF}
SRC_DIR=${PWD}
LIBZMQ=${PWD}/libzmq-build
CPPZMQ=${PWD}/cppzmq-build
# Travis machines have 2 cores
JOBS=2

libzmq_install() {
    curl -L https://github.com/zeromq/libzmq/archive/v"${ZMQ_VERSION}".tar.gz \
      >zeromq.tar.gz
    tar -xvzf zeromq.tar.gz
    if [ "${BUILD_TYPE}" = "cmake" ] ; then
        cmake -Hlibzmq-${ZMQ_VERSION} -B${LIBZMQ} -DWITH_PERF_TOOL=OFF \
                                                  -DZMQ_BUILD_TESTS=OFF \
                                                  -DCMAKE_BUILD_TYPE=Release \
                                                  -DENABLE_DRAFTS=${ENABLE_DRAFTS}
        cmake --build ${LIBZMQ} -- -j${JOBS}
    elif [ "${BUILD_TYPE}" = "pkgconfig" ] ; then
        pushd .
        cd libzmq-${ZMQ_VERSION}
        ./autogen.sh &&
        ./configure --prefix=${LIBZMQ} &&
        make -j${JOBS}
        make install
        popd
    fi
}


# build zeromq first
cppzmq_build() {
    pushd .
    if [ "${COVERAGE}" = "ON" ] ; then
        # to get a valid coverage measurement, we need to build with
        # optimizations disabled, in particular with inlinable functions
        # (which all of our functions are), see also 
        # https://gcc.gnu.org/onlinedocs/gcc/Gcov-and-Optimization.html
        CMAKE_BUILD_TYPE=Debug
    else
        CMAKE_BUILD_TYPE=RelWithDebInfo
    fi
    CMAKE_PREFIX_PATH=${LIBZMQ} \
    cmake -H. -B${CPPZMQ} -DENABLE_DRAFTS=${ENABLE_DRAFTS} \
                          -DCOVERAGE=${COVERAGE} \
                          -DCMAKE_BUILDTYPE=${CMAKE_BUILD_TYPE}
    cmake --build ${CPPZMQ} -- -j${JOBS}
    popd
}

cppzmq_tests() {
    pushd .
    cd ${CPPZMQ}
    if [ "$COVERAGE" == "ON" ] ; then
        lcov --capture --directory . --base-directory ${SRC_DIR} --output-file Coverage.baseline --initial
    fi
    ctest -V -j${JOBS}
    if [ "$COVERAGE" == "ON" ] ; then
        lcov --capture --directory . --base-directory ${SRC_DIR} --output-file Coverage.out
        lcov --add-tracefile Coverage.baseline --add-tracefile Coverage.out --output-file Coverage.combined
        lcov --remove Coverage.combined "cppzmq-build" "tests" --output-file Coverage.combined
        lcov --list Coverage.combined # DIAGNOSTIC OUTPUT
    fi
    popd
}

cppzmq_demo() {
    pushd .
    CMAKE_PREFIX_PATH=${LIBZMQ}:${CPPZMQ} \
    cmake -Hdemo -Bdemo/build
    cmake --build demo/build
    cd demo/build
    ctest -V
    popd
}

if [ "${ZMQ_VERSION}" != "" ] ; then libzmq_install ; fi

cppzmq_build
cppzmq_tests
cppzmq_demo
