cmake_minimum_required(VERSION 3.16)
project(std2pipe C)

set(CMAKE_EXE_LINKER_FLAGS "-static -s")

add_compile_options(
    -Wall
    -Wextra
    -Wshadow
    -Werror

    $<$<CONFIG:Release>:-Os>
    $<$<CONFIG:Release>:-flto>
)

add_executable(std2pipe main.c)
