import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/quran.dart';
import '../main.dart';
import '../services/matcher.dart';
import '../services/parent_report.dart';
import '../services/recognizer.dart';

enum MurajaahPhase { preparing, reading, checking, done, error }

/// Murajaah: anak membaca seluruh rangkaian ayat tanpa dicek per ayat,
/// lalu koreksi ditampilkan di akhir.
class MurajaahController extends ChangeNotifier {
  MurajaahController({
    required this.ayahs,
    required this.threshold,
    required this.title,
  }) {
    _totalLen = ayahs.fold(
        0, (s, a) => s + ArabicMatcher.normalize(a.text).length);
  }

  final List<Ayah> ayahs;
  final double threshold;
  final String title;

  final Recognizer _rec = Recognizer.instance;

  MurajaahPhase phase = MurajaahPhase.preparing;
  String message = 'Menyiapkan…';
  bool micActive = false;
  List<AyahVerdict> verdicts = [];
  List<int> recordedSurahs = [];
  Duration elapsed = Duration.zero;

  late final int _totalLen;
  String _finalText = '';
  String _partialText = '';
  String _partialRaw = '';
  String _rawText = '';
  int _session = -1;
  Timer? _clock;
  DateTime? _startedAt;
  bool _disposed = false;

  String get heardSoFar => _finalText + _partialText;

  /// Perkiraan kemajuan bacaan (berdasarkan panjang teks terdengar).
  double get progress =>
      _totalLen == 0 ? 0 : math.min(1, heardSoFar.length / _totalLen);

  List<AyahVerdict> get mistakes =>
      verdicts.where((v) => v.verdict != Verdict.correct).toList();

  Future<void> start() async {
    final ok = await _rec.init();
    if (!ok) {
      _fail('Pengenal suara tidak tersedia di HP ini. Pastikan aplikasi '
          'Google terpasang dan izin mikrofon diberikan.');
      return;
    }
    _rec.onResult = _onResult;
    _rec.onFatalError = _fail;
    _rec.onListeningChanged = (l) {
      micActive = l;
      _notify();
    };
    _begin();
  }

  void _begin() {
    phase = MurajaahPhase.reading;
    message = 'Silakan mulai membaca sampai selesai, lalu ketuk tombol "Selesai & koreksi".';
    _startedAt ??= DateTime.now();
    _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed = DateTime.now().difference(_startedAt!);
      _notify();
    });
    _notify();
    _rec.start();
  }

  void _fail(String msg) {
    phase = MurajaahPhase.error;
    message = msg;
    _rec.stop();
    _notify();
  }

  Future<void> retry() async {
    if (phase == MurajaahPhase.error) _begin();
  }

  void _onResult(String text, bool isFinal, int session) {
    if (_disposed || phase != MurajaahPhase.reading) return;
    // Sesi dengar baru dimulai tanpa hasil final dari sesi sebelumnya:
    // simpan bacaan sementara sesi lama agar tidak hilang.
    // Hasil terlambat dari sesi lama (sudah disimpan) diabaikan.
    if (session < _session) return;
    if (session != _session) {
      _commitPartial();
      _session = session;
    }
    final norm = ArabicMatcher.normalize(text);
    if (isFinal) {
      // Sebagian HP mengirim hasil final kosong/terpotong setelah jeda;
      // dalam hal itu pakai hasil sementara yang lebih lengkap.
      final useFinal = norm.length >= _partialText.length * 0.6;
      _append(useFinal ? norm : _partialText, useFinal ? text : _partialRaw);
      _partialText = '';
      _partialRaw = '';
    } else {
      _partialText = norm;
      _partialRaw = text;
    }
    _notify();
  }

  void _commitPartial() {
    if (_partialText.isNotEmpty) _append(_partialText, _partialRaw);
    _partialText = '';
    _partialRaw = '';
  }

  void _append(String norm, String raw) {
    _finalText += norm;
    if (raw.isNotEmpty) _rawText = '$_rawText $raw'.trim();
  }

  /// Potongan terakhir yang terdengar (untuk ditampilkan).
  String get heardTail {
    final raw = '$_rawText $_partialRaw'.trim();
    return raw.length > 90 ? '…${raw.substring(raw.length - 90)}' : raw;
  }

  /// Hentikan bacaan dan lakukan koreksi.
  Future<void> finish() async {
    if (phase != MurajaahPhase.reading) return;
    phase = MurajaahPhase.checking;
    message = 'Memeriksa bacaan…';
    _clock?.cancel();
    _notify();
    _commitPartial();
    final heard = _finalText;
    await _rec.stop();
    // Beri kesempatan UI menampilkan status sebelum perhitungan.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    verdicts = ArabicMatcher.review(ayahs, heard, threshold);
    final wrong = {
      for (final v in verdicts)
        if (v.verdict != Verdict.correct) '${v.ayah.surah}:${v.ayah.ayah}'
    };
    recordedSurahs = await ParentReport.instance.recordSession(
      ayahs: ayahs,
      mode: 'Murajaah',
      failed: (a) => wrong.contains('${a.surah}:${a.ayah}'),
      errorsOf: (_) => 0,
    );
    phase = MurajaahPhase.done;
    message = wrong.isEmpty
        ? 'Masya Allah, semua ayat benar!'
        : '${wrong.length} ayat perlu diperbaiki';
    if (wrong.isEmpty) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    _notify();
  }

  /// Ulangi dari awal.
  Future<void> restart() async {
    await _rec.stop();
    _finalText = '';
    _partialText = '';
    _partialRaw = '';
    _rawText = '';
    verdicts = [];
    recordedSurahs = [];
    _startedAt = DateTime.now();
    elapsed = Duration.zero;
    _clock?.cancel();
    _clock = null;
    _begin();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _clock?.cancel();
    _rec.onResult = null;
    _rec.onFatalError = null;
    _rec.onListeningChanged = null;
    _rec.stop();
    super.dispose();
  }
}

class MurajaahScreen extends StatefulWidget {
  const MurajaahScreen({super.key, required this.controller});
  final MurajaahController controller;

  @override
  State<MurajaahScreen> createState() => _MurajaahScreenState();
}

class _MurajaahScreenState extends State<MurajaahScreen> {
  MurajaahController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => c.start());
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
    return Scaffold(
      appBar: AppBar(title: Text('Murajaah • ${c.title}')),
      body: SafeArea(
        child: c.phase == MurajaahPhase.done ? _result() : _reading(),
      ),
    );
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _reading() {
    final q = QuranData.instance;
    final first = c.ayahs.first;
    final last = c.ayahs.last;
    final reading = c.phase == MurajaahPhase.reading;
    final error = c.phase == MurajaahPhase.error;
    final color = error ? AppColors.red : AppColors.green;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${q.surah(first.surah).latin} ${first.ayah} – '
            '${q.surah(last.surah).latin} ${last.ayah}  •  ${c.ayahs.length} ayat',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.black54, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: c.micActive ? 172 : 152,
                    height: c.micActive ? 172 : 152,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.10),
                      border: Border.all(
                          color: c.micActive ? AppColors.orange : color,
                          width: c.micActive ? 6 : 3),
                    ),
                    child: c.phase == MurajaahPhase.checking
                        ? const Padding(
                            padding: EdgeInsets.all(48),
                            child: CircularProgressIndicator(strokeWidth: 6),
                          )
                        : Icon(
                            error
                                ? Icons.error_outline_rounded
                                : (c.micActive
                                    ? Icons.mic_rounded
                                    : Icons.mic_none_rounded),
                            size: 80,
                            color: color),
                  ),
                  const SizedBox(height: 24),
                  if (reading)
                    Text(_fmt(c.elapsed),
                        style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: AppColors.greenDark,
                            fontFeatures: [FontFeature.tabularFigures()])),
                  const SizedBox(height: 8),
                  Text(
                    c.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: error ? AppColors.red : AppColors.greenDark),
                  ),
                  if (reading) ...[
                    const SizedBox(height: 22),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: c.progress,
                        minHeight: 10,
                        color: AppColors.orange,
                        backgroundColor: AppColors.green.withValues(alpha: 0.12),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Perkiraan kemajuan ${(c.progress * 100).round()}%',
                        style: const TextStyle(color: Colors.black45)),
                    if (c.heardTail.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        c.heardTail,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 17, color: Colors.black38),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          if (error)
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi'),
              onPressed: c.retry,
            )
          else if (reading) ...[
            FilledButton.icon(
              icon: const Icon(Icons.fact_check),
              label: const Text('Selesai & koreksi'),
              onPressed: c.finish,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.restart_alt),
              label: const Text('Ulang dari awal'),
              onPressed: c.restart,
            ),
          ],
        ],
      ),
    );
  }

  Widget _result() {
    final q = QuranData.instance;
    final mistakes = c.mistakes;
    final correct = c.verdicts.length - mistakes.length;
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
                'Benar $correct dari ${c.verdicts.length} ayat • waktu ${_fmt(c.elapsed)}',
                style: const TextStyle(color: Colors.white70),
              ),
              if (c.recordedSurahs.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Tercatat di laporan: ${c.recordedSurahs.map((s) => q.surah(s).latin).join(', ')}',
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
                  itemBuilder: (_, i) => _MistakeCard(v: mistakes[i]),
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
                  onPressed: c.restart,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MistakeCard extends StatelessWidget {
  const _MistakeCard({required this.v});
  final AyahVerdict v;

  /// Pecah teks ayat menjadi potongan biasa dan potongan merah.
  static List<TextSpan> _spans(AyahVerdict v) {
    final text = v.ayah.text;
    final wrong = v.wrongChars;
    if (wrong.isEmpty) return [TextSpan(text: text)];
    const red = TextStyle(
      color: AppColors.red,
      backgroundColor: Color(0x1FB3261E),
    );
    final spans = <TextSpan>[];
    var start = 0;
    var cur = wrong.contains(0);
    for (var i = 1; i <= text.length; i++) {
      final w = i < text.length && wrong.contains(i);
      if (i == text.length || w != cur) {
        spans.add(TextSpan(
            text: text.substring(start, i), style: cur ? red : null));
        start = i;
        cur = w;
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final q = QuranData.instance;
    final notRead = v.verdict == Verdict.notRead;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: notRead ? Colors.black26 : AppColors.orange, width: 1.5),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: notRead ? Colors.black12 : AppColors.orangeSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(notRead ? 'Tidak terbaca' : 'Salah',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: notRead ? Colors.black54 : AppColors.orangeDark)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'QS. ${q.surah(v.ayah.surah).latin} ayat ${v.ayah.ayah}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.greenDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
              notRead || v.wrongChars.isEmpty
                  ? 'Bacaan yang benar:'
                  : 'Bacaan yang benar (merah = bagian yang terdengar salah):',
              style: const TextStyle(fontSize: 12.5, color: Colors.black45)),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(children: _spans(v)),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: 24, height: 1.9, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}
