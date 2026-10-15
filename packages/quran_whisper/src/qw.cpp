// Pembungkus tipis whisper.cpp (MIT) untuk aplikasi Sambung Ayat.
#include "qw.h"

#include <string.h>
#include <string>

#include "whisper.h"

static void qw_silent_log(enum ggml_log_level, const char *, void *) {}

extern "C" void *qw_init(const char *model_path) {
  whisper_log_set(qw_silent_log, nullptr);
  struct whisper_context_params cp = whisper_context_default_params();
  cp.use_gpu = false;
  return whisper_init_from_file_with_params(model_path, cp);
}

extern "C" void *qw_init_from_buffer(void *buffer, int32_t size) {
  whisper_log_set(qw_silent_log, nullptr);
  struct whisper_context_params cp = whisper_context_default_params();
  cp.use_gpu = false;
  return whisper_init_from_buffer_with_params(buffer, (size_t)size, cp);
}

extern "C" int32_t qw_transcribe(void *vctx, const float *pcm, int32_t n_samples,
                                 int32_t n_threads, char *out, int32_t out_len) {
  if (vctx == nullptr || out == nullptr || out_len <= 0) return -1;
  auto *ctx = static_cast<struct whisper_context *>(vctx);

  whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  p.n_threads = n_threads > 0 ? n_threads : 4;
  p.language = "ar";
  p.translate = false;
  p.detect_language = false;
  p.no_context = true;        // tiap potongan berdiri sendiri
  p.no_timestamps = true;
  p.print_progress = false;
  p.print_realtime = false;
  p.print_special = false;
  p.print_timestamps = false;
  p.suppress_blank = true;

  if (whisper_full(ctx, p, pcm, n_samples) != 0) return -1;

  std::string text;
  const int n = whisper_full_n_segments(ctx);
  for (int i = 0; i < n; ++i) {
    const char *seg = whisper_full_get_segment_text(ctx, i);
    if (seg != nullptr) {
      text += seg;
      text += ' ';
    }
  }
  size_t len = text.size();
  if (len > (size_t)(out_len - 1)) len = (size_t)(out_len - 1);
  memcpy(out, text.data(), len);
  out[len] = '\0';
  return (int32_t)len;
}

extern "C" void qw_free(void *vctx) {
  if (vctx != nullptr) whisper_free(static_cast<struct whisper_context *>(vctx));
}
