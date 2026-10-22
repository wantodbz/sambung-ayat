"""Siapkan audio uji Murajaah (dijalankan di CI).

- At-Tahrim ayat 1-12 (Syaikh Aiman Suwaid, EveryAyah) disambung menjadi satu
  rekaman "jernih".
- Versi "anak": nada dinaikkan ±4 semiton dan diberi bising latar, untuk
  meniru bacaan anak di rumah.
- Keduanya dipotong di jeda persis seperti aplikasi (lib/services/audio_split.dart)
  lalu disimpan per potongan, beserta teks ayat yang seharusnya.
"""
import array
import json
import math
import os
import subprocess
import sys
import urllib.request
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "benchdata")
SURAH = int(os.environ.get("SURAH", "66"))
FOLDER = "Ayman_Sowaid_64kbps"


def split_on_pauses(pcm, sr=16000):
    """Salinan splitOnPauses() di aplikasi. pcm: list float. Hasil: [(awal, akhir)]."""
    frame = sr // 50
    n_frames = len(pcm) // frame
    if n_frames == 0:
        return []
    rms = []
    for f in range(n_frames):
        o = f * frame
        s = 0.0
        for v in pcm[o:o + frame]:
            s += v * v
        rms.append(math.sqrt(s / frame))
    floor = sorted(rms)[int(n_frames * 0.1)]
    speech_level = max(floor * 3, 0.004)
    max_len, min_len, win = 28 * 50, 12 * 50, 7

    def energy_around(f):
        return sum(rms[max(0, f - win):min(n_frames - 1, f + win) + 1])

    chunks, start = [], 0
    while start < n_frames:
        if n_frames - start <= max_len:
            end = n_frames
        else:
            end, best = start + max_len, float("inf")
            for f in range(start + min_len, start + max_len + 1):
                e = energy_around(f)
                if e < best:
                    best, end = e, f
        loud = sum(1 for f in range(start, end) if rms[f] > speech_level)
        if loud >= 15:
            s = start * frame
            e = len(pcm) if end == n_frames else end * frame
            chunks.append((s, e))
        start = end
    return chunks


def read_wav(path):
    with wave.open(path, "rb") as w:
        assert w.getframerate() == 16000 and w.getnchannels() == 1 and w.getsampwidth() == 2
        data = array.array("h")
        data.frombytes(w.readframes(w.getnframes()))
    return data


def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(samples.tobytes())


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *args], check=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    q = json.load(open(os.path.join(ROOT, "assets", "quran.json"), encoding="utf-8"))
    verses = q["surahs"][SURAH - 1]["verses"]
    with open(os.path.join(OUT, "expected.txt"), "w", encoding="utf-8") as f:
        f.write(" ".join(verses))

    mp3s = []
    for a in range(1, len(verses) + 1):
        name = f"{SURAH:03d}{a:03d}.mp3"
        dst = os.path.join(OUT, name)
        if not os.path.exists(dst):
            urllib.request.urlretrieve(f"https://everyayah.com/data/{FOLDER}/{name}", dst)
        mp3s.append(dst)
    jernih = os.path.join(OUT, "jernih.wav")
    ffmpeg("-i", "concat:" + "|".join(mp3s), "-ar", "16000", "-ac", "1",
           "-c:a", "pcm_s16le", jernih)
    anak = os.path.join(OUT, "anak.wav")
    ffmpeg("-i", jernih,
           "-f", "lavfi", "-i", "anoisesrc=color=pink:amplitude=0.02:sample_rate=16000:seed=7",
           "-filter_complex",
           "[0:a]asetrate=20160,aresample=16000,atempo=0.7937[v];"
           "[v][1:a]amix=inputs=2:duration=first:normalize=0[out]",
           "-map", "[out]", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", anak)

    manifest = {}
    for name, path in (("jernih", jernih), ("anak", anak)):
        data = read_wav(path)
        pcm = [v / 32768.0 for v in data]
        parts = []
        for i, (s, e) in enumerate(split_on_pauses(pcm)):
            p = os.path.join(OUT, f"{name}_{i:02d}.wav")
            write_wav(p, data[s:e])
            parts.append({"wav": p, "sec": round((e - s) / 16000, 2)})
        manifest[name] = {"total_sec": round(len(data) / 16000, 1), "chunks": parts}
        print(f"{name}: {manifest[name]['total_sec']} detik, {len(parts)} potongan "
              f"({', '.join(str(c['sec']) for c in parts)})")
    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)


if __name__ == "__main__":
    sys.exit(main())
