cmake_minimum_required(VERSION 3.15)
project(EasyGifReader CXX)

add_library(EasyGifReader STATIC EasyGifReader.cpp)
target_include_directories(EasyGifReader PUBLIC .)
target_link_libraries(EasyGifReader PUBLIC gif)
