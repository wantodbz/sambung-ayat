import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../main.dart';
import '../services/audio_store.dart';
import '../services/settings.dart';
import 'session_controller.dart';
import 'session_screen.dart';

/// Memilih cakupan latihan: per surat atau per juz.
class RangeScreen extends StatelessWidget {
  const RangeScreen({super.key, required this.mode});

  final SessionMode mode;

  @override
  Widget build(BuildContext context) {
    final q = QuranData.instance;
    final title =
        mode == SessionMode.sambungAyat ? 'Sambung Ayat' : 'Murajaah';
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: AppColors.gold,
            tabs: [Tab(text: 'Per Surat'), Tab(text: 'Per Juz')],
          ),
        ),
        body: TabBarView(
          children: [
            ListView.separated(
              itemCount: 114,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final s = q.surahs[i];
                return ListTile(
                  leading: _NumberBadge(s.number),
                  title: Text(s.latin,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${s.makkiyah ? 'Makkiyah' : 'Madaniyah'} • ${s.count} ayat'),
                  trailing: Text(s.name,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                          fontSize: 20, color: AppColors.green)),
                  onTap: () => _start(ctx, q.rangeSurah(s.number),
                      'QS. ${s.latin}'),
                );
              },
            ),
            ListView.separated(
              itemCount: 30,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final juz = i + 1;
                return ListTile(
                  leading: _NumberBadge(juz),
                  title: Text('Juz $juz',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(q.juzLabel(juz)),
                  trailing: Text('${q.rangeJuz(juz).length} ayat',
                      style: const TextStyle(color: Colors.black54)),
                  onTap: () => _start(ctx, q.rangeJuz(juz), 'Juz $juz'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start(
      BuildContext context, List<Ayah> ayahs, String label) async {
    if (mode == SessionMode.sambungAyat) {
      final ok = await ensureAudio(context, ayahs);
      if (!ok || !context.mounted) return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SessionScreen(
          controller: SessionController(
            mode: mode,
            ayahs: ayahs,
            threshold: Settings.instance.strictness.threshold,
            title: label,
          ),
        ),
      ),
    );
  }
}

/// Pastikan audio untuk rangkaian ayat sudah ada; tawarkan unduh bila belum.
Future<bool> ensureAudio(BuildContext context, List<Ayah> ayahs) async {
  final store = AudioStore.instance;
  final refs = AudioStore.requiredFor(ayahs);
  final missing = await store.missing(refs);
  if (missing.isEmpty) return true;
  if (!context.mounted) return false;
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Unduh audio dulu'),
      content: Text(
          'Murottal untuk ${missing.length} ayat belum tersimpan di HP. '
          'Unduh sekarang? (sekitar ${(missing.length * 0.1).toStringAsFixed(1)} MB, '
          'perlu koneksi internet; cukup sekali)'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unduh')),
      ],
    ),
  );
  if (yes != true || !context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DownloadDialog(refs: refs),
      ) ??
      false;
}

/// Dialog progres unduhan.
class DownloadDialog extends StatefulWidget {
  const DownloadDialog({super.key, required this.refs});
  final List<List<int>> refs;

  @override
  State<DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<DownloadDialog> {
  int _done = 0;
  int _total = 0;
  String? _error;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _error = null);
    try {
      await AudioStore.instance.download(
        widget.refs,
        onProgress: (d, t) {
          if (mounted) setState(() {
            _done = d;
            _total = t;
          });
        },
        isCancelled: () => _cancelled,
      );
      if (mounted && !_cancelled) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _total == 0 ? null : _done / _total;
    return AlertDialog(
      title: Text(_error == null ? 'Mengunduh murottal…' : 'Unduhan gagal'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error == null) ...[
            LinearProgressIndicator(value: p),
            const SizedBox(height: 12),
            Text('$_done dari $_total ayat'),
          ] else
            Text(_error!),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _cancelled = true;
            Navigator.pop(context, false);
          },
          child: const Text('Batal'),
        ),
        if (_error != null)
          FilledButton(onPressed: _run, child: const Text('Coba lagi')),
      ],
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge(this.n);
  final int n;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold, width: 1.5),
      ),
      child: Text('$n',
          style: const TextStyle(
              fontWeight: FontWeight.w700, color: AppColors.greenDark)),
    );
  }
}
