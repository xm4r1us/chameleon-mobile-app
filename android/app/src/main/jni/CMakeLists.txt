cmake_minimum_required(VERSION 3.22.1)
project(recovery C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O2")

add_library(recovery SHARED
    recovery_bridge.c
    crapto1.c
    crypto1.c
    parity.c
    bucketsort.c
    mfkey.c
    nested_util.c
)

find_package(Threads REQUIRED)
target_link_libraries(recovery Threads::Threads)
