import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../main.dart';
import 'session_controller.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.controller});
  final SessionController controller;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  SessionController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    if (SessionController.needsGesture) {
      c.message = 'Ketuk "Mulai" untuk memulai.';
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.start());
    }
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (c.phase == Phase.finished && !_shownFinish) {
      _shownFinish = true;
      _showFinish();
    }
  }

  bool _shownFinish = false;

  @override
  void dispose() {
    c.removeListener(_onChange);
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = c.current;
    final q = QuranData.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: c.progress,
            backgroundColor: AppColors.greenDark,
            color: AppColors.orange,
            minHeight: 4,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (a != null)
                Text(
                  '${q.surah(a.surah).latin} • ayat ${a.ayah}'
                  '   (${c.index + 1}/${c.ayahs.length})',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: 20),
              Expanded(child: Center(child: _StatusCard(c: c))),
              const SizedBox(height: 16),
              if (c.heard.isNotEmpty && c.phase == Phase.listening)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Terdengar: ${c.heard}',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 16, color: Colors.black45),
                  ),
                ),
              _Actions(c: c, onHint: _showHint),
            ],
          ),
        ),
      ),
    );
  }

  void _showHint() {
    final a = c.current;
    if (a == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            'QS. ${QuranData.instance.surah(a.surah).latin} : ${a.ayah}'),
        content: SingleChildScrollView(
          child: Text(
            a.text,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 26, height: 1.9),
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup')),
        ],
      ),
    );
  }

  void _showFinish() {
    final correctFirstTry = c.userAyahs - c.skipped;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.emoji_events, color: AppColors.orange, size: 48),
        title: const Text('Alhamdulillah, selesai'),
        content: Text(
          'Ayat yang Anda baca: ${c.userAyahs}\n'
          'Ayat dilewati: ${c.skipped}\n'
          'Jumlah kesalahan: ${c.totalErrors}\n\n'
          '${c.totalErrors == 0 && c.skipped == 0 ? 'Masya Allah, tanpa kesalahan!' : 'Terus murajaah, semoga Allah mudahkan. ($correctFirstTry ayat tuntas)'}'
          '${c.recordedSurahs.isEmpty ? '' : '\n\nTercatat di laporan: ${c.recordedSurahs.map((s) => QuranData.instance.surah(s).latin).join(', ')}'}',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Kembali'),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.c});
  final SessionController c;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (c.phase) {
      Phase.playing => (Icons.volume_up_rounded, AppColors.orange),
      Phase.listening => (
          c.micActive ? Icons.mic_rounded : Icons.mic_none_rounded,
          AppColors.green
        ),
      Phase.correct => (Icons.check_circle_rounded, AppColors.green),
      Phase.wrong => (Icons.replay_circle_filled_rounded, AppColors.red),
      Phase.finished => (Icons.emoji_events_rounded, AppColors.orange),
      Phase.error => (Icons.error_outline_rounded, AppColors.red),
      Phase.preparing => (Icons.hourglass_top_rounded, Colors.black38),
    };
    final listening = c.phase == Phase.listening && c.micActive;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: listening ? 168 : 150,
          height: listening ? 168 : 150,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.12),
            border: Border.all(color: color, width: listening ? 6 : 3),
          ),
          child: Icon(icon, size: 78, color: color),
        ),
        const SizedBox(height: 28),
        Text(
          c.message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: c.phase == Phase.wrong || c.phase == Phase.error
                ? AppColors.red
                : AppColors.greenDark,
          ),
        ),
        if (c.phase == Phase.listening) ...[
          const SizedBox(height: 10),
          Text(
            c.micActive
                ? 'Mendengarkan…'
                : (c.processing ? 'Memeriksa bacaan…' : 'Menyiapkan mikrofon…'),
            style: const TextStyle(color: Colors.black45),
          ),
        ],
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  static final Expando<bool> _started = Expando();

  const _Actions({required this.c, required this.onHint});
  final SessionController c;
  final VoidCallback onHint;

  @override
  Widget build(BuildContext context) {
    if (SessionController.needsGesture &&
        c.phase == Phase.preparing &&
        _Actions._started[c] != true) {
      return FilledButton.icon(
        icon: const Icon(Icons.play_arrow),
        label: const Text('Mulai'),
        onPressed: () {
          _Actions._started[c] = true;
          c.startFromGesture();
        },
      );
    }
    if (c.phase == Phase.error) {
      return FilledButton.icon(
        icon: const Icon(Icons.refresh),
        label: const Text('Coba lagi'),
        onPressed: c.retry,
      );
    }
    if (c.phase == Phase.finished) return const SizedBox.shrink();
    final userTurn = c.phase == Phase.listening || c.phase == Phase.wrong;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.canGiveUp) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.visibility),
                  label: const Text('Lihat ayat'),
                  onPressed: onHint,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Lewati'),
                  onPressed: c.skip,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.restart_alt),
                label: const Text('Ulangi'),
                onPressed: userTurn ? c.restartAyah : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Selesai membaca'),
                onPressed:
                    c.phase == Phase.listening ? c.finishReading : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
