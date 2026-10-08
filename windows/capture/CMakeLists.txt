cmake_minimum_required(VERSION 3.18)
project(blackgrid_capture LANGUAGES CXX)
if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "Capture boundary requires Windows x64")
endif()

# Input and capture boundary (ADR-0010): plain Win32 only, nothing is
# redistributed. user32 and gdi32 are OS components; kernel32 is implicit.
set(BLACKGRID_CAPTURE_SOURCES capture.cpp frames.cpp hook.cpp)

add_library(blackgrid_capture SHARED ${BLACKGRID_CAPTURE_SOURCES})
target_compile_features(blackgrid_capture PRIVATE cxx_std_20)
target_compile_options(blackgrid_capture PRIVATE /W4 /EHsc /permissive-)
target_compile_definitions(blackgrid_capture PRIVATE BLACKGRID_CAPTURE_EXPORTS)
set_property(TARGET blackgrid_capture PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
target_link_libraries(blackgrid_capture PRIVATE user32 gdi32)

# Native self-test (design D9): same sources, real bgc_* entry points, never
# built by default and never installed.
add_executable(blackgrid_capture_selftest EXCLUDE_FROM_ALL
  selftest.cpp ${BLACKGRID_CAPTURE_SOURCES})
target_compile_features(blackgrid_capture_selftest PRIVATE cxx_std_20)
target_compile_options(blackgrid_capture_selftest PRIVATE /W4 /EHsc /permissive-)
target_compile_definitions(blackgrid_capture_selftest PRIVATE BLACKGRID_CAPTURE_EXPORTS)
set_property(TARGET blackgrid_capture_selftest PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
target_link_libraries(blackgrid_capture_selftest PRIVATE user32 gdi32)
