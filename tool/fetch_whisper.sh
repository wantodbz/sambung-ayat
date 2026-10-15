#!/usr/bin/env bash
# Salin sumber whisper.cpp v1.5.4 (lisensi MIT) ke packages/quran_whisper/src/whisper
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/packages/quran_whisper/src/whisper"
TMP="$(mktemp -d)"
git clone -q --depth 1 --branch v1.5.4 https://github.com/ggerganov/whisper.cpp "$TMP/w"
mkdir -p "$DEST"
for f in whisper.cpp whisper.h ggml.c ggml.h ggml-alloc.c ggml-alloc.h ggml-backend.c \
         ggml-backend.h ggml-backend-impl.h ggml-impl.h ggml-quants.c ggml-quants.h LICENSE; do
  cp "$TMP/w/$f" "$DEST/"
done
rm -rf "$TMP"
echo "whisper.cpp v1.5.4 disalin ke $DEST"
