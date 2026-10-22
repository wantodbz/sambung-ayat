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
// Sama dengan qw_transcribe_ex(..., max_tokens = 0, audio_ctx = 0, flags = 0).
QW_EXPORT int32_t qw_transcribe(void *ctx, const float *pcm, int32_t n_samples,
                                int32_t n_threads, char *out, int32_t out_len);

// Seperti qw_transcribe dengan pengaturan tambahan:
//   max_tokens : batas token per potongan (0 = tanpa batas)
//   audio_ctx  : panjang konteks audio encoder (0 = penuh 30 detik)
//   flags      : bit 0 = perilaku lama (tebakan diulang bila ragu, tanpa
//                penghenti pengulangan) — hanya untuk uji banding.
QW_EXPORT int32_t qw_transcribe_ex(void *ctx, const float *pcm, int32_t n_samples,
                                   int32_t n_threads, int32_t max_tokens,
                                   int32_t audio_ctx, int32_t flags, char *out,
                                   int32_t out_len);

QW_EXPORT void qw_free(void *ctx);

#ifdef __cplusplus
}
#endif
