import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../main.dart';
import '../widgets/mistake_card.dart';
import 'session_controller.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.controller});
  final SessionController controller;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  SessionController get c => widget.controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    if (SessionController.needsGesture) {
      c.message = 'Ketuk "Mulai" untuk memulai.';
    } else {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => c.start());
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final finished = c.phase == Phase.finished;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: finished ? 1 : c.progress,
            backgroundColor: AppColors.greenDark,
            color: AppColors.orange,
            minHeight: 4,
          ),
        ),
      ),
      body: SafeArea(child: finished ? _result() : _session()),
    );
  }

  Widget _session() {
    final a = c.current;
    final q = QuranData.instance;
    return Padding(
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
          Expanded(
            child: Center(
              child: SingleChildScrollView(child: _StatusCard(c: c)),
            ),
          ),
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
                style: const TextStyle(fontSize: 16, color: Colors.black45),
              ),
            ),
          _actions(),
        ],
      ),
    );
  }

  Widget _actions() {
    if (!_started) {
      return FilledButton.icon(
        icon: const Icon(Icons.play_arrow),
        label: const Text('Mulai'),
        onPressed: () {
          setState(() => _started = true);
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
    final listening = c.phase == Phase.listening;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.restart_alt),
            label: const Text('Ulangi'),
            onPressed: listening ? c.restartAyah : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Selesai membaca'),
            onPressed: listening ? c.finishReading : null,
          ),
        ),
      ],
    );
  }

  Widget _result() {
    final q = QuranData.instance;
    final mistakes = c.mistakes;
    final total = c.verdicts.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: mistakes.isEmpty ? AppColors.green : AppColors.greenDark,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Icon(
                  mistakes.isEmpty
                      ? Icons.emoji_events_rounded
                      : Icons.assignment_late_rounded,
                  color: AppColors.orange,
                  size: 44),
              const SizedBox(height: 8),
              Text(c.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'Benar ${c.correctCount} dari $total ayat yang Anda baca',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              if (c.recordedSurahs.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Tercatat di laporan: '
                  '${c.recordedSurahs.map((s) => q.surah(s).latin).join(', ')}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.orange),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: mistakes.isEmpty
              ? const Center(
                  child: Text('Tidak ada ayat yang perlu diperbaiki.',
                      style: TextStyle(color: Colors.black54)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: mistakes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => MistakeCard(v: mistakes[i]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kembali'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.replay),
                  label: const Text('Ulangi'),
                  onPressed: c.restartSession,
                ),
              ),
            ],
          ),
        ),
      ],
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
      Phase.wrong => (Icons.skip_next_rounded, AppColors.orange),
      Phase.finished => (Icons.emoji_events_rounded, AppColors.orange),
      Phase.error => (Icons.error_outline_rounded, AppColors.red),
      Phase.preparing => (Icons.hourglass_top_rounded, Colors.black38),
    };
    final listening = c.phase == Phase.listening;
    final urgent = listening && c.countdown <= 5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: listening && c.micActive ? 168 : 150,
          height: listening && c.micActive ? 168 : 150,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.12),
            border: Border.all(
                color: color, width: listening && c.micActive ? 6 : 3),
          ),
          child: Icon(icon, size: 78, color: color),
        ),
        const SizedBox(height: 24),
        Text(
          c.message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: switch (c.phase) {
              Phase.error => AppColors.red,
              Phase.wrong => AppColors.orangeDark,
              _ => AppColors.greenDark,
            },
          ),
        ),
        if (listening && !c.voiceHeard) ...[
          const SizedBox(height: 18),
          // Hitung mundur hanya sampai suara bacaan pertama terdengar.
          Text(
            '${c.countdown}',
            key: const Key('countdown'),
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w800,
              color: urgent ? AppColors.orangeDark : AppColors.green,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 220,
              child: LinearProgressIndicator(
                value: c.waitSeconds == 0 ? 0 : c.countdown / c.waitSeconds,
                minHeight: 8,
                color: urgent ? AppColors.orange : AppColors.green,
                backgroundColor: AppColors.green.withValues(alpha: 0.12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            c.micActive
                ? 'Silakan mulai membaca sebelum waktu habis'
                : 'Menyiapkan mikrofon…',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black45),
          ),
        ],
        if (listening && c.voiceHeard) ...[
          const SizedBox(height: 14),
          Text(
            c.processing ? 'Memeriksa bacaan…' : 'Mendengarkan bacaan…',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 16,
                color: AppColors.green,
                fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}
