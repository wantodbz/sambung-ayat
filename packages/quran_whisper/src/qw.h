#pragma once
#include <stdint.h>

#if defined(_WIN32)
#define QW_EXPORT __declspec(dllexport)
#else
#define QW_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Muat model whisper.cpp. Mengembalikan NULL bila gagal.
QW_EXPORT void *qw_init(const char *model_path);

// Muat model dari memori (dipakai versi web/WASM).
QW_EXPORT void *qw_init_from_buffer(void *buffer, int32_t size);

// Transkripsi PCM float 16 kHz mono. Teks UTF-8 ditulis ke [out]
// (maks out_len-1 byte). Mengembalikan panjang teks, atau -1 bila gagal.
QW_EXPORT int32_t qw_transcribe(void *ctx, const float *pcm, int32_t n_samples,
                                int32_t n_threads, char *out, int32_t out_len);

QW_EXPORT void qw_free(void *ctx);

#ifdef __cplusplus
}
#endif
