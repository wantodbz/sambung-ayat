// Uji kecepatan & ketepatan pemeriksaan Murajaah (dijalankan di CI).
// Pakai: bench <model> <threads> <flags> <plan.txt>
//   plan.txt: tiap baris "<wav> <max_tokens> <audio_ctx>"
// Keluaran: satu baris JSON per potongan.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <chrono>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "qw.h"
#include "whisper.h"

// WAV PCM 16-bit mono (ditulis oleh prepare.py) -> float -1..1.
static std::vector<float> read_wav(const std::string &path) {
  std::ifstream f(path, std::ios::binary);
  std::vector<char> b((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
  std::vector<float> pcm;
  size_t pos = 12;
  while (pos + 8 <= b.size()) {
    uint32_t size;
    memcpy(&size, &b[pos + 4], 4);
    if (memcmp(&b[pos], "data", 4) == 0) {
      const size_t n = size / 2;
      pcm.resize(n);
      for (size_t i = 0; i < n; ++i) {
        int16_t s;
        memcpy(&s, &b[pos + 8 + i * 2], 2);
        pcm[i] = s / 32768.0f;
      }
      break;
    }
    pos += 8 + size + (size & 1);
  }
  return pcm;
}

static std::string json_escape(const char *s) {
  std::string r;
  for (; *s; ++s) {
    if (*s == '"' || *s == '\\') r += '\\';
    if ((unsigned char)*s < 0x20) continue;
    r += *s;
  }
  return r;
}

int main(int argc, char **argv) {
  if (argc < 5) {
    fprintf(stderr, "pakai: bench <model> <threads> <flags> <plan.txt>\n");
    return 2;
  }
  void *ctx = qw_init(argv[1]);
  if (ctx == nullptr) {
    fprintf(stderr, "model gagal dimuat\n");
    return 1;
  }
  const int threads = atoi(argv[2]);
  const int flags = atoi(argv[3]);
  std::ifstream plan(argv[4]);
  std::string wav;
  int max_tokens = 0, audio_ctx = 0;
  std::vector<char> out(65536);
  auto *wctx = static_cast<whisper_context *>(ctx);
  const int eot = whisper_token_eot(wctx);
  while (plan >> wav >> max_tokens >> audio_ctx) {
    std::vector<float> pcm = read_wav(wav);
    const auto t0 = std::chrono::steady_clock::now();
    const int len = qw_transcribe_ex(ctx, pcm.data(), (int)pcm.size(), threads,
                                     max_tokens, audio_ctx, flags, out.data(),
                                     (int)out.size());
    const double ms = std::chrono::duration<double, std::milli>(
                          std::chrono::steady_clock::now() - t0).count();
    int n_tok = 0;
    for (int i = 0; i < whisper_full_n_segments(wctx); ++i) {
      for (int j = 0; j < whisper_full_n_tokens(wctx, i); ++j) {
        if (whisper_full_get_token_id(wctx, i, j) < eot) ++n_tok;
      }
    }
    printf("{\"wav\":\"%s\",\"sec\":%.2f,\"ms\":%.0f,\"tokens\":%d,\"ok\":%s,\"text\":\"%s\"}\n",
           wav.c_str(), pcm.size() / 16000.0, ms, n_tok, len >= 0 ? "true" : "false",
           json_escape(len > 0 ? out.data() : "").c_str());
    fflush(stdout);
  }
  qw_free(ctx);
  return 0;
}
