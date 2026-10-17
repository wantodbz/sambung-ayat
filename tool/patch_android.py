"""Melengkapi proyek Android hasil `flutter create`:
izin mikrofon & internet, nama aplikasi, ikon, target API, dan kunci tanda tangan."""
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

# Kunci tanda tangan rilis:
# - "tetap"  : kunci lama, untuk APK yang dipasang langsung (menimpa versi lama).
# - "unggah" : kunci unggah Google Play. Berkasnya didekripsi di CI dari secret
#              KUNCI_UNGGAH lalu diberikan lewat UPLOAD_KEYSTORE.
# - TANPA_TANDA_TANGAN=1 : AAB tanpa tanda tangan (ditandatangani terpisah).
keystore = os.path.join(ROOT, "tool", "signing", "debug.keystore").replace("\\", "/")
app = os.path.join(ROOT, "android", "app")
kts = os.path.join(app, "build.gradle.kts")
groovy = os.path.join(app, "build.gradle")
if os.path.isfile(kts):
    path = kts
    block = (
        'android {\n'
        '    packaging {\n'
        '        jniLibs {\n'
        '            useLegacyPackaging = true\n'
        '        }\n'
        '    }\n'
        '    signingConfigs {\n'
        '        create("tetap") {\n'
        f'            storeFile = file("{keystore}")\n'
        '            storePassword = "android"\n'
        '            keyAlias = "androiddebugkey"\n'
        '            keyPassword = "android"\n'
        '        }\n'
        '        create("unggah") {\n'
        '            val ks = System.getenv("UPLOAD_KEYSTORE")\n'
        '            if (ks != null) {\n'
        '                storeFile = file(ks)\n'
        '                storeType = "pkcs12"\n'
        '                storePassword = System.getenv("UPLOAD_KEY_PASSWORD")\n'
        '                keyAlias = "upload"\n'
        '                keyPassword = System.getenv("UPLOAD_KEY_PASSWORD")\n'
        '            }\n'
        '        }\n'
        '    }\n'
    )
    old_sign = r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)'
    new_sign = (
        'signingConfig = when {\n'
        '                System.getenv("UPLOAD_KEYSTORE") != null -> signingConfigs.getByName("unggah")\n'
        '                System.getenv("TANPA_TANDA_TANGAN") != null -> null\n'
        '                else -> signingConfigs.getByName("tetap")\n'
        '            }'
    )
    sdk = [
        (r"compileSdk\s*=\s*flutter\.compileSdkVersion", "compileSdk = 36"),
        (r"targetSdk\s*=\s*flutter\.targetSdkVersion", "targetSdk = 36"),
    ]
    min_sdk = "minSdk = 24"
else:
    path = groovy
    block = (
        'android {\n'
        '    packagingOptions {\n'
        '        jniLibs {\n'
        '            useLegacyPackaging true\n'
        '        }\n'
        '    }\n'
        '    signingConfigs {\n'
        '        tetap {\n'
        f'            storeFile file("{keystore}")\n'
        '            storePassword "android"\n'
        '            keyAlias "androiddebugkey"\n'
        '            keyPassword "android"\n'
        '        }\n'
        '        unggah {\n'
        '            if (System.getenv("UPLOAD_KEYSTORE")) {\n'
        '                storeFile file(System.getenv("UPLOAD_KEYSTORE"))\n'
        '                storeType "pkcs12"\n'
        '                storePassword System.getenv("UPLOAD_KEY_PASSWORD")\n'
        '                keyAlias "upload"\n'
        '                keyPassword System.getenv("UPLOAD_KEY_PASSWORD")\n'
        '            }\n'
        '        }\n'
        '    }\n'
    )
    old_sign = r"signingConfig\s+signingConfigs\.debug"
    new_sign = ('signingConfig System.getenv("UPLOAD_KEYSTORE") ? signingConfigs.unggah : '
                '(System.getenv("TANPA_TANDA_TANGAN") ? null : signingConfigs.tetap)')
    sdk = [
        (r"compileSdk(Version)?\s+flutter\.compileSdkVersion", "compileSdkVersion 36"),
        (r"targetSdk(Version)?\s+flutter\.targetSdkVersion", "targetSdkVersion 36"),
    ]
    min_sdk = "minSdkVersion 24"

with open(path, encoding="utf-8") as f:
    gradle = f.read()
# minSdk 24 (perekam audio & pengenal bacaan offline)
gradle = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", min_sdk, gradle)
# Target API 36: syarat Google Play untuk aplikasi baru & pembaruan sejak 31 Agustus 2026.
for pat, rep in sdk:
    gradle, n = re.subn(pat, rep, gradle)
    if n == 0 and rep not in gradle:
        raise SystemExit("Pengaturan SDK tidak ditemukan (" + rep + ") di " + path)
if "tetap" not in gradle:
    gradle = gradle.replace("android {\n", block, 1)
    gradle, n = re.subn(old_sign, lambda m: new_sign, gradle)
    if n == 0:
        raise SystemExit("Pengaturan tanda tangan rilis tidak ditemukan di " + path)
with open(path, "w", encoding="utf-8") as f:
    f.write(gradle)
print(gradle)

# compileSdk 36 lebih baru daripada yang diuji Android Gradle Plugin bawaan
# Flutter 3.29; peringatannya dimatikan (build tetap normal).
props = os.path.join(ROOT, "android", "gradle.properties")
with open(props, encoding="utf-8") as f:
    p = f.read()
if "suppressUnsupportedCompileSdk" not in p:
    with open(props, "a", encoding="utf-8") as f:
        f.write(("" if p.endswith("\n") else "\n") + "android.suppressUnsupportedCompileSdk=36\n")
print("Patch Android selesai.")
