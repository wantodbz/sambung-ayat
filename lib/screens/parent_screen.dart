import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../main.dart';
import '../services/parent_report.dart';

/// Pengawasan Orang Tua: laporan surat yang sudah dibaca dengan benar.
/// Anak boleh melihat; hanya orang tua (dengan kata sandi) yang bisa mereset.
class ParentScreen extends StatefulWidget {
  const ParentScreen({super.key});

  @override
  State<ParentScreen> createState() => _ParentScreenState();
}

class _ParentScreenState extends State<ParentScreen> {
  final _report = ParentReport.instance;

  static const _bulan = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', //
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  String _date(DateTime d) =>
      '${d.day} ${_bulan[d.month - 1]} ${d.year}, '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final q = QuranData.instance;
    final entries = _report.entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengawasan Orang Tua'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'reset') _reset();
              if (v == 'password') _changePassword();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'reset', child: Text('Reset laporan')),
              PopupMenuItem(
                  value: 'password',
                  child: Text(_report.hasPassword
                      ? 'Ubah kata sandi'
                      : 'Buat kata sandi')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_report.hasPassword)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.orangeSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.orange),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Kata sandi orang tua belum dibuat',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.orangeDark)),
                  const SizedBox(height: 4),
                  const Text(
                      'Buat kata sandi agar hanya orang tua yang bisa mereset laporan. '
                      'Jika sebelumnya sudah pernah dibuat, berarti data aplikasi telah dihapus.'),
                  const SizedBox(height: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.orange),
                    onPressed: _changePassword,
                    child: const Text('Buat kata sandi'),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.green,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: entries.length / 114,
                        strokeWidth: 7,
                        color: AppColors.orange,
                        backgroundColor: Colors.white24,
                      ),
                      Text('${entries.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'surat dari 114 sudah dibaca dengan benar sampai selesai',
                    style: TextStyle(color: Colors.white, fontSize: 15.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Belum ada surat yang tercatat.\n\nSurat tercatat bila dibaca sampai '
                'selesai dan semua ayatnya benar, lewat Sambung Ayat maupun Murajaah.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            )
          else
            for (final e in entries)
              Card(
                elevation: 0,
                color: Colors.white,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                      color: AppColors.green.withValues(alpha: 0.15)),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.orangeSoft,
                    foregroundColor: AppColors.orangeDark,
                    child: Text('${e.surah}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  title: Text(q.surah(e.surah).latin,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${_date(e.date)} • ${e.mode}'
                      '${e.times > 1 ? ' • ${e.times}x lulus' : ''}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${e.errors}',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: e.errors == 0
                                  ? AppColors.green
                                  : AppColors.orangeDark)),
                      const Text('kesalahan',
                          style: TextStyle(fontSize: 11, color: Colors.black45)),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 8),
          const Text(
            'Kesalahan = jumlah percobaan yang salah sebelum ayat dibaca benar '
            '(Sambung Ayat). Tanggal menunjukkan kapan terakhir lulus.',
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  Future<String?> _askPassword(String title, {String? hint}) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Kata sandi',
            helperText: hint,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _changePassword() async {
    if (_report.hasPassword) {
      final old = await _askPassword('Masukkan kata sandi lama');
      if (old == null) return;
      if (!_report.verify(old)) {
        _snack('Kata sandi salah.');
        return;
      }
    }
    final p1 = await _askPassword('Kata sandi baru',
        hint: 'Minimal 4 karakter. Simpan baik-baik, tidak bisa dipulihkan.');
    if (p1 == null) return;
    if (p1.length < 4) {
      _snack('Kata sandi minimal 4 karakter.');
      return;
    }
    final p2 = await _askPassword('Ulangi kata sandi baru');
    if (p2 == null) return;
    if (p1 != p2) {
      _snack('Kata sandi tidak sama. Silakan ulangi.');
      return;
    }
    await _report.setPassword(p1);
    if (!mounted) return;
    setState(() {});
    _snack('Kata sandi orang tua tersimpan.');
  }

  Future<void> _reset() async {
    if (!_report.hasPassword) {
      _snack('Buat kata sandi orang tua terlebih dahulu.');
      return;
    }
    final p = await _askPassword('Reset laporan',
        hint: 'Hanya orang tua. Semua catatan surat akan dihapus.');
    if (p == null) return;
    final ok = await _report.reset(p);
    if (!mounted) return;
    if (ok) {
      setState(() {});
      _snack('Laporan telah direset.');
    } else {
      _snack('Kata sandi salah. Laporan tidak direset.');
    }
  }
}
