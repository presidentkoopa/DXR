cmake_minimum_required(VERSION 3.15)
project(giflib C)

set(GIFLIB_SOURCES
    dgif_lib.c
    egif_lib.c
    gifalloc.c
    gif_err.c
    gif_font.c
    gif_hash.c
    openbsd-reallocarray.c
    quantize.c
)

add_library(gif STATIC ${GIFLIB_SOURCES})
target_include_directories(gif PUBLIC .)
if(MSVC)
    target_compile_definitions(gif PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()
