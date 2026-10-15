import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../main.dart';
import '../services/audio_store.dart';
import 'range_screen.dart';

/// Kelola unduhan murottal per surat.
class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  Map<int, int> _counts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final store = AudioStore.instance;
    await store.available(refresh: true);
    final counts = <int, int>{};
    for (var s = 1; s <= 114; s++) {
      counts[s] = await store.downloadedCount(s);
    }
    if (mounted) {
      setState(() {
        _counts = counts;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = QuranData.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Unduhan Audio')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: 115,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Murottal Syaikh Abdurrahman as-Sudais diunduh per surat '
                      'dan disimpan di HP, sehingga menu Sambung Ayat bisa '
                      'memutar audio tanpa internet. Murajaah tidak memerlukan audio.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  );
                }
                final s = q.surahs[i - 1];
                final have = _counts[s.number] ?? 0;
                final full = have >= s.count;
                return ListTile(
                  title: Text('${s.number}. ${s.latin}'),
                  subtitle: Text(full
                      ? 'Tersimpan (${s.count} ayat)'
                      : have == 0
                          ? 'Belum diunduh • ${s.count} ayat'
                          : 'Sebagian: $have dari ${s.count} ayat'),
                  trailing: full
                      ? IconButton(
                          tooltip: 'Hapus',
                          icon: const Icon(Icons.delete_outline,
                              color: AppColors.red),
                          onPressed: () => _delete(s),
                        )
                      : IconButton(
                          tooltip: 'Unduh',
                          icon: const Icon(Icons.download,
                              color: AppColors.green),
                          onPressed: () => _download(s),
                        ),
                );
              },
            ),
    );
  }

  Future<void> _download(Surah s) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DownloadDialog(
          refs: AudioStore.requiredFor(QuranData.instance.rangeSurah(s.number))),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${s.latin} selesai diunduh')));
    }
    await _refresh();
  }

  Future<void> _delete(Surah s) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus audio ${s.latin}?'),
        content: const Text('Audio bisa diunduh lagi kapan saja.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (yes == true) {
      await AudioStore.instance.deleteSurah(s.number);
      await _refresh();
    }
  }
}
