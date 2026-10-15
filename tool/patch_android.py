"""Melengkapi proyek Android hasil `flutter create`:
izin mikrofon & internet, nama aplikasi, ikon, dan kunci tanda tangan tetap."""
import os
import re
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
manifest = os.path.join(ROOT, "android", "app", "src", "main", "AndroidManifest.xml")

with open(manifest, encoding="utf-8") as f:
    xml = f.read()

perms = (
    '    <uses-permission android:name="android.permission.INTERNET"/>\n'
    '    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n'
)
if "RECORD_AUDIO" not in xml:
    xml = re.sub(r"(<manifest[^>]*>\s*\n)", r"\1" + perms, xml, count=1)

xml = re.sub(r'android:label="[^"]*"', 'android:label="Sambung Ayat"', xml, count=1)

intent = (
    '        <intent>\n'
    '            <action android:name="android.speech.RecognitionService" />\n'
    '        </intent>\n'
)
if "android.speech.RecognitionService" not in xml:
    if "<queries>" in xml:
        xml = xml.replace("<queries>\n", "<queries>\n" + intent, 1)
    else:
        xml = xml.replace("</manifest>", "    <queries>\n" + intent + "    </queries>\n</manifest>", 1)

with open(manifest, "w", encoding="utf-8") as f:
    f.write(xml)
print(xml)

# Ikon aplikasi
res = os.path.join(ROOT, "android", "app", "src", "main", "res")
icons = os.path.join(ROOT, "tool", "icons")
for d in os.listdir(icons):
    src = os.path.join(icons, d, "ic_launcher.png")
    if os.path.isfile(src):
        dst_dir = os.path.join(res, d)
        os.makedirs(dst_dir, exist_ok=True)
        shutil.copy(src, os.path.join(dst_dir, "ic_launcher.png"))

# Kunci tanda tangan tetap agar pembaruan APK bisa dipasang menimpa versi lama.
home_android = os.path.join(os.path.expanduser("~"), ".android")
os.makedirs(home_android, exist_ok=True)
shutil.copy(os.path.join(ROOT, "tool", "signing", "debug.keystore"),
            os.path.join(home_android, "debug.keystore"))
print("Patch Android selesai.")
