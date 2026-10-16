"""Periksa kelengkapan murottal per ayat di EveryAyah (dijalankan di GitHub Actions)."""
import json
import os
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

FOLDER = sys.argv[1] if len(sys.argv) > 1 else "Ayman_Sowaid_64kbps"
BASE = f"https://everyayah.com/data/{FOLDER}/"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
q = json.load(open(os.path.join(ROOT, "assets", "quran.json"), encoding="utf-8"))
names = [f"{s:03d}{a:03d}.mp3"
         for s, sur in enumerate(q["surahs"], 1)
         for a in range(1, len(sur["verses"]) + 1)]


def check(name):
    for _ in range(3):
        try:
            req = urllib.request.Request(BASE + name, method="HEAD")
            with urllib.request.urlopen(req, timeout=30) as r:
                return name, r.status == 200 and int(r.headers.get("Content-Length", "1")) > 0
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return name, False
        except Exception:
            pass
    return name, None  # tidak pasti (galat jaringan)


with ThreadPoolExecutor(32) as ex:
    results = list(ex.map(check, names))

missing = [n for n, ok in results if ok is False]
unknown = [n for n, ok in results if ok is None]
summary = (f"{FOLDER} :: Total ayat: {len(names)} | tersedia: {len(names) - len(missing) - len(unknown)} "
      f"| tidak ada: {len(missing)} | tidak pasti: {len(unknown)}")
print(summary)
print(f"::notice title=Audio {FOLDER}::" + summary)
if missing:
    print(f"::warning title=Tidak ada di {FOLDER}::" + " ".join(missing[:200]))
if missing:
    print("Tidak ada:", " ".join(missing[:300]))
if unknown:
    print("Tidak pasti:", " ".join(unknown[:100]))
sys.exit(1 if missing else 0)
