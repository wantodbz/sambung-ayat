// Pembungkus tipis whisper.cpp (MIT) untuk aplikasi Sambung Ayat.
#include "qw.h"

#include <math.h>
#include <string.h>

#include <string>
#include <vector>

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

namespace {

// Penjaga selama menebak: batas jumlah token dan penghenti "ocehan"
// (model mengulang kata/potongan kata yang sama terus-menerus).
struct Guard {
  int max_tokens;  // 0 = tanpa batas
  int eot;
};

// Apakah akhir urutan berisi blok n token yang sama >= reps kali berturut-turut?
bool ends_with_repeats(const whisper_token_data *t, int n_tokens, int n, int reps) {
  if (n_tokens < n * reps) return false;
  for (int r = 1; r < reps; ++r) {
    for (int k = 0; k < n; ++k) {
      if (t[n_tokens - 1 - k].id != t[n_tokens - 1 - k - r * n].id) return false;
    }
  }
  return true;
}

void guard_cb(struct whisper_context *ctx, struct whisper_state *,
              const whisper_token_data *tokens, int n_tokens, float *logits,
              void *user) {
  const Guard *g = static_cast<const Guard *>(user);
  bool stop = g->max_tokens > 0 && n_tokens >= g->max_tokens;
  for (int n = 1; n <= 12 && !stop; ++n) {
    stop = ends_with_repeats(tokens, n_tokens, n, n == 1 ? 6 : 4);
  }
  if (!stop) return;
  // Paksa selesai: hanya token akhir (EOT) yang boleh dipilih.
  const int n_vocab = whisper_n_vocab(ctx);
  for (int i = 0; i < n_vocab; ++i) logits[i] = -INFINITY;
  logits[g->eot] = 0.0f;
}

// Sisa ocehan di ujung teks: blok n token yang muncul berturut-turut
// (>= 3 kali, atau >= 4 kali untuk satu token) disisakan satu.
void trim_trailing_repeats(std::vector<whisper_token> &ids) {
  bool changed = true;
  while (changed) {
    changed = false;
    for (int n = 1; n <= 12 && !changed; ++n) {
      const int sz = (int)ids.size();
      int reps = 1;
      while (sz >= n * (reps + 1)) {
        bool same = true;
        for (int k = 0; k < n; ++k) {
          if (ids[sz - 1 - k] != ids[sz - 1 - k - reps * n]) {
            same = false;
            break;
          }
        }
        if (!same) break;
        ++reps;
      }
      if (reps >= (n == 1 ? 4 : 3)) {
        ids.resize(sz - (reps - 1) * n);
        changed = true;
      }
    }
  }
}

}  // namespace

extern "C" int32_t qw_transcribe_ex(void *vctx, const float *pcm, int32_t n_samples,
                                    int32_t n_threads, int32_t max_tokens,
                                    int32_t audio_ctx, int32_t flags, char *out,
                                    int32_t out_len) {
  if (vctx == nullptr || out == nullptr || out_len <= 0) return -1;
  auto *ctx = static_cast<struct whisper_context *>(vctx);
  const bool legacy = (flags & 1) != 0;

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

  Guard guard = {max_tokens, whisper_token_eot(ctx)};
  if (!legacy) {
    // Sekali tebak. Bawaan whisper.cpp mengulang pemeriksaan satu potongan
    // hingga 6 kali (sebagian dengan 5 tebakan sekaligus) bila model ragu —
    // inilah yang membuat pemeriksaan bisa berjalan puluhan menit.
    p.temperature_inc = 0.0f;
    p.greedy.best_of = 1;
    p.suppress_non_speech_tokens = true;
    p.logits_filter_callback = guard_cb;
    p.logits_filter_callback_user_data = &guard;
    if (audio_ctx > 0 && audio_ctx < whisper_n_audio_ctx(ctx)) p.audio_ctx = audio_ctx;
  }

  if (whisper_full(ctx, p, pcm, n_samples) != 0) return -1;

  // Susun teks dari token (token khusus seperti EOT/bahasa dilewati).
  const whisper_token eot = whisper_token_eot(ctx);
  std::vector<whisper_token> ids;
  const int n_seg = whisper_full_n_segments(ctx);
  for (int i = 0; i < n_seg; ++i) {
    const int n_tok = whisper_full_n_tokens(ctx, i);
    for (int j = 0; j < n_tok; ++j) {
      const whisper_token id = whisper_full_get_token_id(ctx, i, j);
      if (id < eot) ids.push_back(id);
    }
  }
  if (!legacy) trim_trailing_repeats(ids);

  std::string text;
  for (whisper_token id : ids) {
    const char *s = whisper_token_to_str(ctx, id);
    if (s != nullptr) text += s;
  }
  size_t len = text.size();
  if (len > (size_t)(out_len - 1)) len = (size_t)(out_len - 1);
  memcpy(out, text.data(), len);
  out[len] = '\0';
  return (int32_t)len;
}

extern "C" int32_t qw_transcribe(void *vctx, const float *pcm, int32_t n_samples,
                                 int32_t n_threads, char *out, int32_t out_len) {
  return qw_transcribe_ex(vctx, pcm, n_samples, n_threads, 0, 0, 0, out, out_len);
}

extern "C" void qw_free(void *vctx) {
  if (vctx != nullptr) whisper_free(static_cast<struct whisper_context *>(vctx));
}
