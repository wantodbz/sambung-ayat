# Sambung Ayat

Aplikasi Android untuk latihan hafalan Al-Qur'an dengan murottal pilihan (Syaikh Aiman Rusydi Suwaid, Syaikh Mahmud Khalil Al-Hushari, Syaikh Muhammad Ayyub, Syaikh Ali Al-Hudzaifi, Syaikh Abdullah Ali Bashfar).

- **Sambung Ayat**: HP membaca ayat ke-1, Anda membaca ayat ke-2, HP ayat ke-3, dan seterusnya. Bacaan yang salah/tidak selesai (lanjut otomatis setelah diam 3–7 detik sesuai pengaturan, bawaan 5 detik), atau tidak dimulai dalam 15 detik, dicatat dan sesi tetap berlanjut; koreksinya tampil di akhir.
- **Murajaah**: Anda membaca sendiri seluruh ayat sampai selesai; bacaan diperiksa di HP (tanpa internet) sambil Anda membaca, lalu koreksi tampil di akhir.
- Cakupan: per surat atau per juz. Audio diunduh per surat sesuai kebutuhan, terpisah per qari.

Pembuat: **Abu Syafiq**, Perumahan Ar-Raihaan Blok B7.

## Memasang

- **Android**: lewat Google Play (sedang disiapkan). APK uji tetap tersedia di tab **Releases** (`SambungAyat.apk`).
- **iPhone**: buka https://wantodbz.github.io/sambung-ayat/ di Safari, lalu "Tambahkan ke Layar Utama". Bila dibuka dari Layar Utama, Sambung Ayat memakai model pengecek di HP (diunduh sekali), karena pengenal suara Safari tidak tersedia di mode itu.

Kebijakan privasi: https://wantodbz.github.io/sambung-ayat/privasi.html

## Google Play

- Setiap build juga menghasilkan berkas `.aab` (target API 36) untuk diunggah ke Google Play.
- Kunci unggah tersimpan terenkripsi di `tool/signing/upload.p12.enc`. Bila secret repo `KUNCI_UNGGAH` diisi, AAB langsung ditandatangani (`SambungAyat.aab`); bila belum, AAB dibuat tanpa tanda tangan.
- Grafis halaman toko ada di folder `store/`.

## Catatan

- Pengecekan memeriksa lafaz/hafalan, **bukan** tajwid atau makhraj.
- Sambung Ayat memakai pengenal suara bawaan HP (Google) sehingga membutuhkan internet; Murajaah diperiksa di HP tanpa internet.
- Teks Al-Qur'an: Rasm Utsmani dari QuranEnc.com melalui paket `quran-json` (CC BY 4.0). Audio: EveryAyah.com.
- APK dibangun otomatis oleh GitHub Actions (`.github/workflows/build.yml`).
