import 'package:flutter/material.dart';

import '../main.dart';
import '../services/settings.dart';
import 'about_screen.dart';
import 'download_screen.dart';
import 'parent_screen.dart';
import 'range_screen.dart';
import 'session_controller.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Pengaturan',
                  icon: const Icon(Icons.tune),
                  onPressed: () => _showSettings(context),
                ),
                IconButton(
                  tooltip: 'Tentang Aplikasi',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AboutScreen())),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'بِسْمِ اللّٰهِ الرَّحْمٰنِ الرَّحِيْمِ',
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 24, color: AppColors.green),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sambung Ayat',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.greenDark),
            ),
            const SizedBox(height: 4),
            const Text(
              'Latihan hafalan bersama murottal\nSyaikh Abdurrahman as-Sudais',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 28),
            _MenuCard(
              icon: Icons.record_voice_over,
              title: 'Sambung Ayat',
              subtitle:
                  'HP membaca satu ayat, Anda melanjutkan ayat berikutnya. Bergantian sampai selesai.',
              onTap: () => _open(context, SessionMode.sambungAyat),
            ),
            const SizedBox(height: 14),
            _MenuCard(
              icon: Icons.menu_book,
              title: 'Murajaah',
              subtitle:
                  'Baca sampai selesai tanpa jeda, koreksi ditampilkan di akhir.',
              onTap: () => _open(context, SessionMode.murajaah),
            ),
            const SizedBox(height: 14),
            _MenuCard(
              icon: Icons.shield_outlined,
              title: 'Pengawasan Orang Tua',
              subtitle: 'Laporan surat yang sudah dibaca anak dengan benar.',
              light: true,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ParentScreen())),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Kelola Unduhan Audio'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const DownloadScreen())),
            ),
            const SizedBox(height: 28),
            const Text(
              'Catatan: aplikasi mengecek kebenaran lafaz (hafalan), '
              'bukan tajwid atau makhraj.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, SessionMode mode) {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => RangeScreen(mode: mode)));
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final cur = Settings.instance.strictness;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ketelitian pengecekan',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  for (final s in Strictness.values)
                    RadioListTile<Strictness>(
                      value: s,
                      groupValue: cur,
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.label),
                      subtitle: Text(s.hint),
                      onChanged: (v) async {
                        if (v == null) return;
                        await Settings.instance.setStrictness(v);
                        setState(() {});
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.light = false,
  });

  final bool light;

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = light ? AppColors.greenDark : Colors.white;
    final sub = light ? Colors.black54 : Colors.white70;
    return Material(
      color: light ? AppColors.orangeSoft : AppColors.green,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: light ? AppColors.green : AppColors.orange,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: fg,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(color: sub, fontSize: 13.5)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: sub),
            ],
          ),
        ),
      ),
    );
  }
}
