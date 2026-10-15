cmake_minimum_required(VERSION 3.10)
project(quran_whisper_library VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Sumber whisper.cpp v1.5.4 (MIT) disalin ke src/whisper oleh tool/fetch_whisper.sh
set(W ${CMAKE_CURRENT_SOURCE_DIR}/whisper)

add_library(quran_whisper SHARED
  qw.cpp
  ${W}/whisper.cpp
  ${W}/ggml.c
  ${W}/ggml-alloc.c
  ${W}/ggml-backend.c
  ${W}/ggml-quants.c
)

target_include_directories(quran_whisper PRIVATE ${W} ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(quran_whisper PRIVATE NDEBUG GGML_USE_CPU)
target_compile_options(quran_whisper PRIVATE -O3 -fno-finite-math-only)

if (ANDROID)
  set_target_properties(quran_whisper PROPERTIES OUTPUT_NAME "quran_whisper")
  target_link_libraries(quran_whisper PRIVATE log m)
  # Halaman memori 16 KB (Android 15+)
  target_link_options(quran_whisper PRIVATE "-Wl,-z,max-page-size=16384")
else()
  find_package(Threads REQUIRED)
  target_link_libraries(quran_whisper PRIVATE Threads::Threads m)
endif()
