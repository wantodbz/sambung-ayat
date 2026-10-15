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
keystore = os.path.join(ROOT, "tool", "signing", "debug.keystore").replace("\\", "/")
app = os.path.join(ROOT, "android", "app")
kts = os.path.join(app, "build.gradle.kts")
groovy = os.path.join(app, "build.gradle")
if os.path.isfile(kts):
    path = kts
    block = (
        'android {\n'
        '    signingConfigs {\n'
        '        create("tetap") {\n'
        f'            storeFile = file("{keystore}")\n'
        '            storePassword = "android"\n'
        '            keyAlias = "androiddebugkey"\n'
        '            keyPassword = "android"\n'
        '        }\n'
        '    }\n'
    )
    old_sign = 'signingConfigs.getByName("debug")'
    new_sign = 'signingConfigs.getByName("tetap")'
else:
    path = groovy
    block = (
        'android {\n'
        '    signingConfigs {\n'
        '        tetap {\n'
        f'            storeFile file("{keystore}")\n'
        '            storePassword "android"\n'
        '            keyAlias "androiddebugkey"\n'
        '            keyPassword "android"\n'
        '        }\n'
        '    }\n'
    )
    old_sign = "signingConfigs.debug"
    new_sign = "signingConfigs.tetap"
with open(path, encoding="utf-8") as f:
    gradle = f.read()
if "tetap" not in gradle:
    gradle = gradle.replace("android {\n", block, 1)
    if old_sign not in gradle:
        raise SystemExit("Pengaturan tanda tangan rilis tidak ditemukan di " + path)
    gradle = gradle.replace(old_sign, new_sign)
with open(path, "w", encoding="utf-8") as f:
    f.write(gradle)
print(gradle)
print("Patch Android selesai.")
