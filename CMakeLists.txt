cmake_minimum_required(VERSION 3.20)

project(re9mp LANGUAGES CXX)

add_library(re9mp SHARED
    src/re9mp_native.cpp
)

target_compile_features(re9mp PRIVATE cxx_std_17)
target_include_directories(re9mp PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/external
)

target_compile_definitions(re9mp PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    UNICODE
    _UNICODE
)

target_link_libraries(re9mp PRIVATE
    ws2_32
    iphlpapi
    version
)

set_target_properties(re9mp PROPERTIES
    OUTPUT_NAME "re9mp"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
)
