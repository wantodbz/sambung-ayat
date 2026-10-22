import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/quran.dart';
import '../main.dart';
import '../platform/platform.dart';
import '../services/audio_split.dart';
import '../services/matcher.dart';
import '../services/model_store.dart';
import '../services/parent_report.dart';
import '../services/settings.dart';
import '../widgets/mistake_card.dart';
import '../widgets/model_picker.dart';

enum MurajaahPhase {
  preparing,
  needModel,
  downloading,
  ready, // versi web: menunggu ketukan "Mulai membaca"
  reading,
  checking,
  done,
  error
}

/// Murajaah: anak membaca seluruh rangkaian ayat. Suara direkam utuh tanpa
/// putus, lalu setelah "Selesai" diproses di perangkat (tanpa internet) oleh
/// model Whisper khusus bacaan Al-Qur'an, dan dikoreksi.
class MurajaahController extends ChangeNotifier {
  MurajaahController({
    required this.ayahs,
    required this.threshold,
    required this.title,
  });

  final List<Ayah> ayahs;
  final double threshold;
  final String title;

  final MurajaahIO _io = murajaahIO;
  Timer? _levelPoll;
  StreamSubscription<TxEvent>? _trSub;

  MurajaahPhase phase = MurajaahPhase.preparing;
  String message = 'Menyiapkan…';
  bool micActive = false;
  double level = 0; // 0..1, tinggi suara saat merekam
  List<AyahVerdict> verdicts = [];
  List<int> recordedSurahs = [];
  Duration elapsed = Duration.zero;

  // Proses pengunduhan model / koreksi.
  double progress = 0;
  String progressLabel = '';
  String heardTail = '';

  QuranModel model = Settings.instance.model;
  Timer? _clock;
  DateTime? _startedAt;
  bool _disposed = false;
  bool _cancelDownload = false;

  // Native: rekaman dipotong di jeda dan diperiksa sambil anak membaca,
  // sehingga setelah "Selesai" hanya sisa potongan terakhir yang diproses.
  bool get _live => _io.supportsLive;
  LiveSplitter? _splitter;
  LiveTranscriber? _tx;
  StreamSubscription<TxEvent>? _txSub;
  Completer<String?>? _liveDone; // null = selesai, teks = galat
  final List<String> _liveTexts = [];
  DateTime? _checkStarted;
  int _doneAtCheck = 0;

  /// Native: mengganti model saat merekam berarti mulai ulang (pemeriksaan
  /// sudah berjalan dengan model sebelumnya).
  bool get restartsOnModelChange => _live;

  List<AyahVerdict> get mistakes =>
      verdicts.where((v) => v.verdict != Verdict.correct).toList();

  /// Hapus sisa rekaman (dipanggil saat aplikasi dibuka).
  static Future<void> deleteRecording() => murajaahIO.cleanup();

  Future<void> start() async {
    model = Settings.instance.model;
    if (!await _io.hasModel(model)) {
      phase = MurajaahPhase.needModel;
      message = 'Murajaah membutuhkan model pengenal bacaan Al-Qur\'an. '
          'Unduh sekali saja, setelah itu bisa dipakai tanpa internet.';
      _notify();
      return;
    }
    await _afterModelReady();
  }

  Future<void> _afterModelReady() async {
    if (_io.needsGesture) {
      phase = MurajaahPhase.ready;
      message = 'Ketuk "Mulai membaca", lalu bacalah sampai selesai.';
      _notify();
      return;
    }
    await _beginRecording();
  }

  /// Versi web: dipanggil langsung dari ketukan tombol "Mulai membaca".
  Future<void> startFromGesture() async {
    final opened = _io.openRecorder(); // harus dipanggil sinkron di ketukan
    if (!await opened) {
      _fail('Izin mikrofon belum diberikan. Izinkan mikrofon untuk situs ini '
          'di pengaturan Safari, lalu coba lagi.');
      return;
    }
    await _beginRecording();
  }

  /// Unduh model pilihan [m].
  Future<void> downloadModel(QuranModel m) async {
    model = m;
    await Settings.instance.setModel(m);
    phase = MurajaahPhase.downloading;
    message = 'Mengunduh model ${m.label}…';
    progress = 0;
    progressLabel = '';
    _cancelDownload = false;
    _notify();
    try {
      await _io.downloadModel(
        m,
        isCancelled: () => _cancelDownload || _disposed,
        onProgress: (r, t) {
          progress = t > 0 ? r / t : 0;
          progressLabel = t > 0
              ? '${(r / 1048576).toStringAsFixed(1)} / ${(t / 1048576).toStringAsFixed(1)} MB'
              : '${(r / 1048576).toStringAsFixed(1)} MB';
          _notify();
        },
      );
      if (_disposed || _cancelDownload) return;
      if (!await _io.hasModel(m)) {
        throw Exception('Berkas model tidak lengkap.');
      }
      await _afterModelReady();
    } catch (e) {
      _fail('Model gagal diunduh. Periksa koneksi internet lalu coba lagi.\n($e)');
    }
  }

  void cancelDownload() {
    _cancelDownload = true;
    phase = MurajaahPhase.needModel;
    message = 'Unduhan dibatalkan.';
    _notify();
  }

  Future<void> _beginRecording() async {
    if (!await _io.openRecorder()) {
      _fail('Izin mikrofon belum diberikan. Aktifkan di pengaturan HP.');
      return;
    }
    try {
      if (_live) {
        await _startLive();
      } else {
        await _io.startRecording();
      }
    } catch (e) {
      _fail('Perekaman gagal dimulai: $e');
      return;
    }
    micActive = true;
    phase = MurajaahPhase.reading;
    message = 'Silakan mulai membaca sampai selesai, '
        'lalu ketuk tombol "Selesai & koreksi".';
    _startedAt = DateTime.now();
    elapsed = Duration.zero;
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed = DateTime.now().difference(_startedAt!);
      _notify();
    });
    _levelPoll?.cancel();
    _levelPoll = Timer.periodic(const Duration(milliseconds: 150), (_) {
      level = _io.level;
      _notify();
    });
    _notify();
  }

  /// Native: siapkan pemeriksa (model dimuat di latar belakang) lalu
  /// alirkan rekaman ke pemotong; tiap potongan yang siap langsung diperiksa.
  Future<void> _startLive() async {
    await _cancelLive();
    _liveTexts.clear();
    _checkStarted = null;
    final splitter = _splitter = LiveSplitter();
    final done = _liveDone = Completer<String?>();
    final tx = _tx = await _io.openLiveTranscriber(model);
    _txSub = tx.events.listen((ev) {
      if (ev.error != null) {
        if (!done.isCompleted) done.complete(ev.error);
        // Gagal saat anak masih membaca (mis. model rusak): beri tahu sekarang.
        if (phase == MurajaahPhase.reading) _fail('Pemrosesan gagal: ${ev.error}');
        return;
      }
      if (ev.finished) {
        if (!done.isCompleted) done.complete(null);
        return;
      }
      _liveTexts.add(ev.text);
      if (phase == MurajaahPhase.checking) {
        _showProgress(_liveTexts.length, tx.submitted);
      }
    }, onDone: () {
      if (!done.isCompleted) done.complete(null);
    });
    await _io.startLiveRecording((samples) {
      if (!identical(_splitter, splitter) || !identical(_tx, tx)) return;
      for (final c in splitter.add(samples)) {
        tx.add(c);
      }
    });
  }

  Future<void> _cancelLive() async {
    await _txSub?.cancel();
    _txSub = null;
    final tx = _tx;
    _tx = null;
    _splitter = null;
    await tx?.cancel();
  }

  void _showProgress(int done, int total) {
    progress = total == 0 ? 0 : done / total;
    var label = 'Bagian $done dari $total';
    final started = _checkStarted;
    if (started != null && done < total && done > _doneAtCheck) {
      final per = DateTime.now().difference(started).inMilliseconds /
          1000 /
          (done - _doneAtCheck);
      label += ' • sisa ±${_fmtSec((per * (total - done)).round())}';
    }
    progressLabel = label;
    final t = _liveTexts.join(' ').trim();
    heardTail = t.length > 90 ? '…${t.substring(t.length - 90)}' : t;
    _notify();
  }

  void _stopTimers() {
    _clock?.cancel();
    _levelPoll?.cancel();
    _levelPoll = null;
    micActive = false;
    level = 0;
  }

  /// Hentikan perekaman yang sedang berjalan lalu buang rekamannya.
  Future<void> _stopAndDiscard() async {
    _stopTimers();
    await _cancelLive();
    await _io.discardRecording();
  }

  void _fail(String msg) {
    phase = MurajaahPhase.error;
    message = msg;
    _stopAndDiscard();
    _notify();
  }

  Future<void> retry() async {
    if (phase != MurajaahPhase.error) return;
    verdicts = [];
    await start();
  }

  /// Ganti model koreksi. Bila model belum diunduh, rekaman dihentikan,
  /// model diunduh, lalu perekaman dimulai ulang.
  Future<void> switchModel(QuranModel m) async {
    await Settings.instance.setModel(m);
    model = m;
    if (await _io.hasModel(m)) {
      if (phase == MurajaahPhase.needModel || phase == MurajaahPhase.error) {
        await _afterModelReady();
      } else if (_live && phase == MurajaahPhase.reading) {
        // Pemeriksaan sudah berjalan dengan model lama: mulai ulang.
        await _stopAndDiscard();
        await _beginRecording();
      } else {
        _notify();
      }
      return;
    }
    await _stopAndDiscard();
    await downloadModel(m);
  }

  /// Hentikan rekaman, proses dengan model, lalu koreksi.
  Future<void> finish() async {
    if (phase != MurajaahPhase.reading) return;
    _stopTimers();
    phase = MurajaahPhase.checking;
    message = 'Memproses bacaan…';
    progress = 0;
    progressLabel = 'Menyiapkan rekaman';
    _notify();

    final texts = _live ? await _finishLive() : await _finishBatch();
    if (texts == null || _disposed) return;

    // Teks apa adanya (berharakat) agar bagian yang salah bisa ditampilkan.
    verdicts = ArabicMatcher.review(ayahs, texts.join(' '), threshold);
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

  /// Native: kirim sisa rekaman, lalu tunggu antrean pemeriksaan habis.
  /// Mengembalikan teks tiap potongan, atau null bila gagal.
  Future<List<String>?> _finishLive() async {
    final tx = _tx;
    final splitter = _splitter;
    final done = _liveDone;
    if (tx == null || splitter == null || done == null) {
      _fail('Rekaman tidak tersedia. Silakan ulangi.');
      return null;
    }
    try {
      await _io.stopLiveRecording();
    } catch (_) {}
    for (final c in splitter.finish()) {
      tx.add(c);
    }
    _splitter = null;
    if (tx.submitted == 0) {
      _fail('Tidak ada suara bacaan yang terekam. Pastikan mikrofon tidak '
          'tertutup lalu ulangi.');
      return null;
    }
    tx.close();
    _checkStarted = DateTime.now();
    _doneAtCheck = _liveTexts.length;
    _showProgress(_liveTexts.length, tx.submitted);
    final err = await done.future;
    if (_disposed || !identical(_tx, tx)) return null;
    await _txSub?.cancel();
    _txSub = null;
    _tx = null;
    if (err != null) {
      _fail('Pemrosesan gagal: $err');
      return null;
    }
    return List.of(_liveTexts);
  }

  /// Web: rekaman utuh dipotong di jeda lalu diperiksa satu per satu.
  Future<List<String>?> _finishBatch() async {
    final List<Float32List> chunks;
    try {
      // Rekaman langsung dihapus setelah dimuat ke memori.
      final pcm = await _io.stopRecording();
      chunks = pcm == null ? [] : splitOnPauses(pcm);
    } catch (e) {
      await _io.discardRecording();
      _fail('Rekaman tidak bisa dibaca: $e');
      return null;
    }
    if (chunks.isEmpty) {
      _fail('Tidak ada suara bacaan yang terekam. Pastikan mikrofon tidak '
          'tertutup lalu ulangi.');
      return null;
    }

    final texts = <String>[];
    final started = DateTime.now();
    final done = Completer<String?>();
    progressLabel = 'Bagian 0 dari ${chunks.length}';
    _notify();
    _trSub = _io.transcribe(model, chunks).listen((ev) {
      if (ev.error != null) {
        if (!done.isCompleted) done.complete(ev.error);
        return;
      }
      if (ev.finished) {
        if (!done.isCompleted) done.complete(null);
        return;
      }
      texts.add(ev.text);
      progress = ev.done / ev.total;
      final spent = DateTime.now().difference(started).inSeconds;
      final left = (spent / ev.done * (ev.total - ev.done)).round();
      progressLabel = 'Bagian ${ev.done} dari ${ev.total}'
          '${ev.done < ev.total ? ' • sisa ±${_fmtSec(left)}' : ''}';
      final t = texts.join(' ').trim();
      heardTail = t.length > 90 ? '…${t.substring(t.length - 90)}' : t;
      _notify();
    }, onDone: () {
      if (!done.isCompleted) done.complete(null);
    });
    final err = await done.future;
    _trSub = null;
    if (_disposed) return null;
    if (err != null) {
      _fail('Pemrosesan gagal: $err');
      return null;
    }
    return texts;
  }

  static String _fmtSec(int s) =>
      s >= 60 ? '${s ~/ 60} mnt ${s % 60} dtk' : '$s dtk';

  /// Ulangi dari awal.
  Future<void> restart() async {
    await _trSub?.cancel();
    _trSub = null;
    await _stopAndDiscard();
    verdicts = [];
    recordedSurahs = [];
    heardTail = '';
    progress = 0;
    await _beginRecording();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelDownload = true;
    _stopTimers();
    _trSub?.cancel();
    _cancelLive();
    _io.closeRecorder();
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
    // Layar mati membuat HP memperlambat pemeriksaan (bisa sangat lama).
    keepScreenOn(true);
    WidgetsBinding.instance.addPostFrameCallback((_) => c.start());
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    keepScreenOn(false);
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

  Future<void> _pickModel() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Model koreksi',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                  'Model yang tidak dipakai tetap tersimpan, jadi bisa '
                  'berganti kapan saja tanpa unduh ulang.',
                  style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              ModelPicker(onSelected: (_) => Navigator.pop(ctx)),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    final m = Settings.instance.model;
    final ready = await murajaahIO.hasModel(m);
    if (m != c.model || !ready) {
      if ((!ready || c.restartsOnModelChange) &&
          c.phase == MurajaahPhase.reading &&
          c.elapsed.inSeconds > 5) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ready ? 'Ganti ke model ${m.label}?' : 'Unduh model ${m.label}?'),
            content: Text(ready
                ? 'Bacaan sedang diperiksa dengan model ${c.model.label}. Bila '
                    'diganti, rekaman yang sedang berjalan dihentikan dan '
                    'dimulai lagi dari awal.'
                : 'Model ini belum diunduh. Rekaman yang sedang berjalan akan '
                    'dihentikan dan dihapus, lalu dimulai lagi setelah unduhan selesai.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(ready ? 'Ganti' : 'Unduh')),
            ],
          ),
        );
        if (ok != true) {
          await Settings.instance.setModel(c.model);
          return;
        }
      }
      await c.switchModel(m);
    }
  }

  Widget _reading() {
    final q = QuranData.instance;
    final first = c.ayahs.first;
    final last = c.ayahs.last;
    final ph = c.phase;
    final reading = ph == MurajaahPhase.reading;
    final checking = ph == MurajaahPhase.checking;
    final downloading = ph == MurajaahPhase.downloading;
    final error = ph == MurajaahPhase.error;
    final color = error ? AppColors.red : AppColors.green;
    final IconData icon = switch (ph) {
      MurajaahPhase.error => Icons.error_outline_rounded,
      MurajaahPhase.needModel || MurajaahPhase.downloading =>
        Icons.download_rounded,
      MurajaahPhase.reading => Icons.mic_rounded,
      MurajaahPhase.ready => Icons.mic_none_rounded,
      _ => Icons.hourglass_top_rounded,
    };
    final ring = reading ? 6.0 + c.level * 10 : 3.0;
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
          if (reading || error || ph == MurajaahPhase.needModel ||
              ph == MurajaahPhase.ready)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ActionChip(
                  avatar: const Icon(Icons.memory, size: 18,
                      color: AppColors.green),
                  label: Text('Model: ${c.model.label} · Ganti'),
                  backgroundColor: AppColors.orangeSoft,
                  side: BorderSide.none,
                  onPressed: _pickModel,
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 172,
                      height: 172,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.10),
                        border: Border.all(
                            color: reading ? AppColors.orange : color,
                            width: ring),
                      ),
                      child: checking
                          ? const Padding(
                              padding: EdgeInsets.all(52),
                              child: CircularProgressIndicator(strokeWidth: 6),
                            )
                          : Icon(icon, size: 80, color: color),
                    ),
                    const SizedBox(height: 24),
                    if (reading) ...[
                      Text(_fmt(c.elapsed),
                          style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: AppColors.greenDark,
                              fontFeatures: [FontFeature.tabularFigures()])),
                      const Text('Sedang merekam',
                          style: TextStyle(color: AppColors.orangeDark)),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      c.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: error ? AppColors.red : AppColors.greenDark),
                    ),
                    if (checking || downloading) ...[
                      const SizedBox(height: 22),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: c.progress > 0 ? c.progress : null,
                          minHeight: 10,
                          color: AppColors.orange,
                          backgroundColor:
                              AppColors.green.withValues(alpha: 0.12),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(c.progressLabel,
                          style: const TextStyle(color: Colors.black45)),
                    ],
                    if (checking && c.heardTail.isNotEmpty) ...[
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
                    if (ph == MurajaahPhase.needModel) ...[
                      const SizedBox(height: 20),
                      for (final m in QuranModel.values)
                        Card(
                          elevation: 0,
                          color: Colors.white,
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                                color: m == QuranModel.akurat
                                    ? AppColors.orange
                                    : Colors.black12),
                          ),
                          child: ListTile(
                            title: Text('Model ${m.label}'
                                '${m == QuranModel.akurat ? ' (disarankan)' : ''}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text(m.hint),
                            trailing: const Icon(Icons.download,
                                color: AppColors.green),
                            onTap: () => c.downloadModel(m),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (error)
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi'),
              onPressed: c.retry,
            )
          else if (ph == MurajaahPhase.ready)
            FilledButton.icon(
              icon: const Icon(Icons.mic),
              label: const Text('Mulai membaca'),
              onPressed: c.startFromGesture,
            )
          else if (downloading)
            OutlinedButton(
              onPressed: c.cancelDownload,
              child: const Text('Batalkan unduhan'),
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
