cmake_minimum_required(VERSION 3.10)
project(quran_whisper_library VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Sumber whisper.cpp v1.5.4 (MIT) disalin ke src/whisper oleh tool/fetch_whisper.sh
set(W ${CMAKE_CURRENT_SOURCE_DIR}/whisper)
set(QW_SOURCES
  qw.cpp
  ${W}/whisper.cpp
  ${W}/ggml.c
  ${W}/ggml-alloc.c
  ${W}/ggml-backend.c
  ${W}/ggml-quants.c
)

# qw_library(<nama> [flag kompilasi tambahan...])
function(qw_library name)
  add_library(${name} SHARED ${QW_SOURCES})
  target_include_directories(${name} PRIVATE ${W} ${CMAKE_CURRENT_SOURCE_DIR})
  target_compile_definitions(${name} PRIVATE NDEBUG GGML_USE_CPU)
  target_compile_options(${name} PRIVATE -O3 -fno-finite-math-only ${ARGN})
  if (ANDROID)
    target_link_libraries(${name} PRIVATE log m)
    # Halaman memori 16 KB (Android 15+)
    target_link_options(${name} PRIVATE "-Wl,-z,max-page-size=16384")
  else()
    find_package(Threads REQUIRED)
    target_link_libraries(${name} PRIVATE Threads::Threads m)
  endif()
endfunction()

qw_library(quran_whisper)

# Varian untuk prosesor ARMv8.2+ dengan instruksi dot-product & fp16 (umumnya
# HP keluaran 2019 ke atas): ±2x lebih cepat pada uji At-Tahrim. Aplikasi
# memilihnya saat berjalan hanya bila prosesor mendukung.
if (ANDROID AND ANDROID_ABI STREQUAL "arm64-v8a")
  qw_library(quran_whisper_dp -march=armv8.2-a+dotprod+fp16)
endif()
