import 'package:flutter/material.dart';

import '../main.dart';

/// Kebijakan privasi di dalam aplikasi (isi sama dengan web/privasi.html).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const url = 'https://wantodbz.github.io/sambung-ayat/privasi.html';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kebijakan Privasi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          const Text('Berlaku sejak 17 Oktober 2026',
              style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          const Text(
            'Sambung Ayat adalah aplikasi latihan hafalan Al-Qur\'an yang dibuat '
            'oleh Abu Syafiq (Perumahan Ar-Raihaan Blok B7). Halaman ini '
            'menjelaskan data apa saja yang diproses aplikasi dan bagaimana '
            'caranya.',
            style: TextStyle(height: 1.5),
          ),
          for (final s in _sections) _SectionView(s),
          const SizedBox(height: 20),
          const Text('Versi daring:', style: TextStyle(color: Colors.black54)),
          const SelectableText(url, style: TextStyle(color: AppColors.green)),
        ],
      ),
    );
  }
}

class _Sec {
  const _Sec(this.title, {this.points = const [], this.note});
  final String title;
  final List<String> points;
  final String? note;
}

const _sections = <_Sec>[
  _Sec('Ringkasan', points: [
    'Tanpa akun, iklan, analitik, atau pelacakan.',
    'Pembuat aplikasi tidak memiliki server; aplikasi tidak mengirim data '
        'Anda kepada pembuat aplikasi.',
    'Suara hanya diproses sesaat untuk memeriksa bacaan dan tidak disimpan.',
    'Laporan dan pengaturan hanya tersimpan di perangkat Anda.',
  ]),
  _Sec('Mikrofon dan suara', points: [
    'Mikrofon hanya aktif saat sesi latihan berjalan.',
    'Sambung Ayat: saat giliran Anda membaca, suara diproses oleh layanan '
        'pengenal suara bawaan perangkat (di Android: layanan Google; di versi '
        'web: layanan peramban atau model di perangkat) untuk diubah menjadi '
        'teks saat itu juga. Aplikasi tidak menyimpan rekaman; teksnya hanya '
        'dipakai untuk mencocokkan bacaan. Pemrosesan oleh layanan tersebut '
        'mengikuti kebijakan privasi penyedianya.',
    'Murajaah: suara direkam sementara di perangkat, diperiksa langsung di '
        'perangkat tanpa internet, lalu rekamannya segera dihapus, termasuk '
        'bila sesi dibatalkan.',
  ]),
  _Sec('Data yang tersimpan di perangkat',
      points: [
        'Laporan bacaan untuk orang tua: nomor surat, tanggal, mode latihan, '
            'dan jumlah kesalahan.',
        'Kata sandi orang tua, disimpan dalam bentuk tersandi (hash), bukan '
            'teks aslinya.',
        'Pengaturan aplikasi (qari, model, tingkat ketelitian).',
        'Berkas murottal dan model yang Anda unduh.',
      ],
      note: 'Data ini tidak dikirim ke mana pun dan terhapus bila aplikasi '
          'dihapus atau datanya dibersihkan.'),
  _Sec('Unduhan dari pihak ketiga',
      note: 'Audio murottal diunduh dari EveryAyah.com, sedangkan model '
          'pengenal bacaan diunduh dari GitHub. Seperti permintaan internet '
          'pada umumnya, penyedia tersebut dapat mencatat informasi teknis '
          '(misalnya alamat IP) sesuai kebijakan masing-masing. Aplikasi tidak '
          'menyertakan data pribadi apa pun dalam permintaan itu.'),
  _Sec('Anak-anak',
      note: 'Aplikasi ini dirancang untuk dipakai anak-anak dengan pendampingan '
          'orang tua. Aplikasi tidak meminta nama, email, nomor telepon, '
          'lokasi, kontak, foto, atau data pribadi lain dari anak maupun '
          'orang tua.'),
  _Sec('Izin yang digunakan', points: [
    'Mikrofon: mendengarkan bacaan saat latihan.',
    'Internet dan status jaringan: mengunduh murottal dan model, serta untuk '
        'pengenal suara.',
  ]),
  _Sec('Perubahan kebijakan',
      note: 'Bila kebijakan ini berubah, versi terbaru diterbitkan di halaman '
          'ini dengan tanggal berlaku yang baru.'),
  _Sec('Kontak',
      note: 'Pertanyaan tentang kebijakan ini dapat disampaikan melalui email '
          'pengembang yang tercantum di halaman Sambung Ayat di Google Play.'),
];

class _SectionView extends StatelessWidget {
  const _SectionView(this.s);
  final _Sec s;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.green)),
          const SizedBox(height: 6),
          for (final p in s.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ',
                      style: TextStyle(
                          color: AppColors.orange,
                          fontWeight: FontWeight.w900)),
                  Expanded(
                      child: Text(p, style: const TextStyle(height: 1.45))),
                ],
              ),
            ),
          if (s.note != null)
            Text(s.note!, style: const TextStyle(height: 1.45)),
        ],
      ),
    );
  }
}
