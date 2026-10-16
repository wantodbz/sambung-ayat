import 'package:flutter/material.dart';

import '../main.dart';
import '../platform/platform.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tentang Aplikasi')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 96,
                height: 96,
                color: AppColors.green,
                child: const Icon(Icons.menu_book,
                    color: AppColors.orange, size: 52),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Sambung Ayat',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          Text(streamsAudio ? 'Versi web 2.5' : 'Versi 2.5 (uji)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 24),
          _Section(
            title: 'Pembuat Aplikasi',
            children: const [
              _Row(icon: Icons.person, label: 'Nama', value: 'Abu Syafiq'),
              _Row(
                  icon: Icons.home,
                  label: 'Alamat',
                  value: 'Perumahan Ar-Raihaan Blok B7'),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Sumber',
            children: const [
              _Row(
                  icon: Icons.volume_up,
                  label: 'Murottal',
                  value: 'Pilihan qari dari EveryAyah.com: Syaikh Aiman Rusydi '
                      'Suwaid, Syaikh Mahmud Khalil Al-Hushari, Syaikh Muhammad '
                      'Ayyub, Syaikh Ali Al-Hudzaifi, Syaikh Abdullah Ali Bashfar'),
              _Row(
                  icon: Icons.menu_book,
                  label: 'Teks Al-Qur\'an',
                  value:
                      'Rasm Utsmani dari The Noble Qur\'an Encyclopedia (QuranEnc.com), '
                      'melalui paket quran-json (CC BY 4.0)'),
              _Row(
                  icon: Icons.mic,
                  label: 'Pengenal suara',
                  value: 'Layanan pengenal suara bawaan Android (Google)'),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Catatan Penting',
            children: const [
              Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Aplikasi ini mengecek kebenaran lafaz/hafalan, bukan tajwid, '
                  'makhraj, atau panjang-pendek bacaan. Pengecekan bacaan '
                  'membutuhkan koneksi internet. Tetap belajar dan setorkan '
                  'hafalan kepada guru.',
                  style: TextStyle(height: 1.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.orange.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.green)),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.green),
      title: Text(label,
          style: const TextStyle(fontSize: 13, color: Colors.black54)),
      subtitle: Text(value,
          style: const TextStyle(fontSize: 16, color: Colors.black87)),
    );
  }
}
