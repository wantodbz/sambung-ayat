#!/usr/bin/env bash
# Kompilasi program uji: "bench" (umum) dan, di ARM, "bench_dp" (instruksi
# dot-product + fp16 seperti prosesor HP keluaran 2019 ke atas).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
S="$ROOT/packages/quran_whisper/src"

build() { # $1 = nama keluaran, $2 = flag arsitektur
  local O F
  O="$(mktemp -d)"
  F="-O3 -DNDEBUG -fno-finite-math-only -pthread $2"
  for f in ggml ggml-alloc ggml-backend ggml-quants; do
    gcc $F -std=gnu11 -D_GNU_SOURCE -I"$S/whisper" -c "$S/whisper/$f.c" -o "$O/$f.o"
  done
  g++ $F -std=gnu++11 -D_GNU_SOURCE -I"$S/whisper" -c "$S/whisper/whisper.cpp" -o "$O/whisper.o"
  g++ $F -std=gnu++11 -D_GNU_SOURCE -I"$S" -I"$S/whisper" -c "$S/qw.cpp" -o "$O/qw.o"
  g++ $F -std=gnu++11 -I"$S" -I"$S/whisper" "$ROOT/tool/bench/bench.cpp" "$O"/*.o -o "$ROOT/$1" -lm
}

if [ "$(uname -m)" = "aarch64" ]; then
  build bench "-march=armv8-a"
  build bench_dp "-march=armv8.2-a+dotprod+fp16" || build bench_dp "-march=armv8.2-a+dotprod"
else
  build bench "-march=native"
fi
ls -la "$ROOT"/bench*
