"""Jalankan uji banding pemeriksaan Murajaah dan laporkan sebagai notice CI.

Ukuran yang dilaporkan per pengaturan:
- waktu proses total dan kelipatannya terhadap lama audio (RT; < 1 berarti
  lebih cepat dari durasi bacaan),
- CER: persentase huruf yang berbeda dari teks ayat (setelah dinormalkan
  seperti pencocok di aplikasi: harakat, alif, dan hamzah diabaikan),
- token per detik audio (untuk menentukan batas token yang aman).
"""
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, "benchdata")
THREADS = os.environ.get("THREADS", "4")
TIMEOUT = int(os.environ.get("TIMEOUT", "1800"))


def norm(s):
    s = re.sub("[ؐ-ًؚ-ٰٟۖ-ۭـ]", "", s)
    s = re.sub("[ءآأإاٱ-ٵ]", "", s)
    s = s.replace("ؤ", "و").replace("ئ", "ي")
    s = s.replace("ى", "ي").replace("ة", "ه")
    return re.sub("[^ء-ي]", "", s)


def cer(hyp, ref):
    a, b = norm(hyp), norm(ref)
    if not b:
        return 0.0
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i] + [0] * len(b)
        for j, cb in enumerate(b, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb))
        prev = cur
    return 100.0 * prev[-1] / len(b)


def audio_ctx(sec):
    return min(1500, int(sec * 50) + 64)


def run(binary, model, flags, chunks, use_ctx):
    plan = os.path.join(DATA, "plan.txt")
    with open(plan, "w") as f:
        for c in chunks:
            f.write(f"{c['wav']} 0 {audio_ctx(c['sec']) if use_ctx else 0}\n")
    t0 = time.time()
    try:
        p = subprocess.run([os.path.join(ROOT, binary), model, THREADS, str(flags), plan],
                           capture_output=True, text=True, timeout=TIMEOUT)
        lines = [json.loads(l) for l in p.stdout.splitlines() if l.startswith("{")]
        timed_out = False
    except subprocess.TimeoutExpired as e:
        out = e.stdout.decode() if isinstance(e.stdout, bytes) else (e.stdout or "")
        lines = [json.loads(l) for l in out.splitlines() if l.startswith("{")]
        timed_out = True
    return lines, time.time() - t0, timed_out


def main():
    manifest = json.load(open(os.path.join(DATA, "manifest.json")))
    expected = open(os.path.join(DATA, "expected.txt"), encoding="utf-8").read()
    arm = os.path.exists(os.path.join(ROOT, "bench_dp"))
    configs = [
        ("lama", "bench", "ggml-quran-base.bin", 1, False),
        ("baru", "bench", "ggml-quran-base.bin", 0, False),
        ("baru+ctx", "bench", "ggml-quran-base.bin", 0, True),
        ("cepat+ctx", "bench", "ggml-quran-tiny.bin", 0, True),
    ]
    if arm:
        configs.append(("baru+ctx-dotprod", "bench_dp", "ggml-quran-base.bin", 0, True))
    cpu = "ARM" if arm else "x86"
    for audio in ("jernih", "anak", "sulit"):
        info = manifest[audio]
        parts = []
        for name, binary, model, flags, use_ctx in configs:
            lines, secs, timed_out = run(binary, model, flags, info["chunks"], use_ctx)
            text = " ".join(l["text"] for l in lines)
            done = len(lines)
            rates = sorted(l["tokens"] / max(l["sec"], 0.5) for l in lines) or [0]
            msg = (f"{name}: {secs:.0f} dtk ({secs / info['total_sec']:.2f}x durasi)"
                   + (f" TIMEOUT {done}/{len(info['chunks'])}" if timed_out else "")
                   + f", CER {cer(text, expected) if not timed_out else float('nan'):.1f}%"
                   + f", token/dtk maks {rates[-1]:.1f}")
            parts.append(msg)
            print(f"== {cpu} {audio} {msg}\n{text[:400]}\n", flush=True)
        print(f"::notice title={cpu} {audio} ({info['total_sec']:.0f} dtk, "
              f"{len(info['chunks'])} potongan)::" + " | ".join(parts), flush=True)


if __name__ == "__main__":
    sys.exit(main())
