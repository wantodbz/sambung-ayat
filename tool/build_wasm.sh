#!/usr/bin/env bash
# Kompilasi whisper.cpp (v1.5.4) + pembungkus qw ke WebAssembly untuk versi web.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/packages/quran_whisper/src"
O="$(mktemp -d)"
FLAGS="-O3 -msimd128 -DNDEBUG -fno-finite-math-only"
for f in ggml ggml-alloc ggml-backend ggml-quants; do
  emcc $FLAGS -std=gnu11 -D_GNU_SOURCE -I"$S/whisper" -c "$S/whisper/$f.c" -o "$O/$f.o"
done
em++ $FLAGS -std=gnu++11 -D_GNU_SOURCE -I"$S/whisper" -c "$S/whisper/whisper.cpp" -o "$O/whisper.o"
em++ $FLAGS -std=gnu++11 -D_GNU_SOURCE -I"$S" -I"$S/whisper" -c "$S/qw.cpp" -o "$O/qw.o"
# Argumen "node": varian uji untuk Node.js (CI), selain itu varian web worker.
if [ "${1:-}" = "node" ]; then
  OUT=/tmp/qw_node/qw.js; ENV=node; mkdir -p /tmp/qw_node
else
  OUT="$ROOT/web/whisper/qw.js"; ENV=worker
fi
em++ $FLAGS "$O"/*.o -o "$OUT" \
  -sMODULARIZE=1 -sEXPORT_NAME=createQW -sENVIRONMENT=$ENV \
  -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=67108864 -sMAXIMUM_MEMORY=2147483648 \
  -sSTACK_SIZE=8388608 \
  -sEXPORTED_FUNCTIONS='["_qw_init_from_buffer","_qw_transcribe","_qw_transcribe_ex","_qw_free","_malloc","_free"]' \
  -sEXPORTED_RUNTIME_METHODS='["UTF8ToString","HEAPU8","HEAPF32"]'
echo "WASM selesai: $OUT"
