"""Melengkapi proyek iOS hasil `flutter create`: izin mikrofon & pengenalan
suara, nama aplikasi, versi iOS minimum, dan ikon aplikasi."""
import json
import os
import plistlib
import re

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IOS = os.path.join(ROOT, "ios")

# 1. Info.plist
plist_path = os.path.join(IOS, "Runner", "Info.plist")
with open(plist_path, "rb") as f:
    info = plistlib.load(f)
info["CFBundleDisplayName"] = "Sambung Ayat"
info["CFBundleName"] = "Sambung Ayat"
info["NSMicrophoneUsageDescription"] = (
    "Mikrofon dipakai untuk mendengarkan bacaan Al-Qur'an Anda "
    "pada menu Sambung Ayat dan Murajaah.")
info["NSSpeechRecognitionUsageDescription"] = (
    "Pengenalan suara dipakai untuk memeriksa bacaan pada menu Sambung Ayat.")
info["ITSAppUsesNonExemptEncryption"] = False
info["UIFileSharingEnabled"] = False
with open(plist_path, "wb") as f:
    plistlib.dump(info, f)
print("Info.plist diperbarui")

# 2. Podfile: versi iOS minimum
podfile = os.path.join(IOS, "Podfile")
with open(podfile, encoding="utf-8") as f:
    pod = f.read()
pod = re.sub(r"^#?\s*platform :ios, '[\d.]+'", "platform :ios, '13.0'", pod, flags=re.M)
if "platform :ios" not in pod:
    pod = "platform :ios, '13.0'\n" + pod
with open(podfile, "w", encoding="utf-8") as f:
    f.write(pod)
print("Podfile: iOS 13.0")

# 3. Target penerapan proyek
pbx = os.path.join(IOS, "Runner.xcodeproj", "project.pbxproj")
with open(pbx, encoding="utf-8") as f:
    proj = f.read()
proj = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 13.0;", proj)
with open(pbx, "w", encoding="utf-8") as f:
    f.write(proj)

# 4. Ikon aplikasi (iOS tidak menerima transparansi: isi latar hijau)
src = Image.open(os.path.join(ROOT, "tool", "icons", "icon_1024.png")).convert("RGBA")
bg = Image.new("RGBA", src.size, (14, 92, 70, 255))
bg.alpha_composite(src)
full = bg.convert("RGB")
iconset = os.path.join(IOS, "Runner", "Assets.xcassets", "AppIcon.appiconset")
with open(os.path.join(iconset, "Contents.json"), encoding="utf-8") as f:
    contents = json.load(f)
for img in contents.get("images", []):
    name = img.get("filename")
    if not name:
        continue
    pt = float(img["size"].split("x")[0])
    scale = float(img.get("scale", "1x").rstrip("x"))
    px = int(round(pt * scale))
    full.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))
print("Ikon iOS dibuat")
