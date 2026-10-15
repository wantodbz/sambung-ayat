import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../data/quran.dart';
import '../services/audio_store.dart';
import '../services/matcher.dart';
import '../services/recognizer.dart';

enum SessionMode { sambungAyat, murajaah }

enum Phase { preparing, playing, listening, correct, wrong, finished, error }

/// Mengatur jalannya satu sesi Sambung Ayat atau Murajaah.
///
/// Sambung Ayat : HP membaca ayat ke-1, pengguna ayat ke-2, HP ayat ke-3, dst.
/// Murajaah     : pengguna membaca semua ayat; aplikasi hanya mengecek.
class SessionController extends ChangeNotifier {
  SessionController({
    required this.mode,
    required this.ayahs,
    required this.threshold,
    required this.title,
  });

  final SessionMode mode;
  final List<Ayah> ayahs;
  final double threshold;
  final String title;

  final Recognizer _rec = Recognizer.instance;
  AudioPlayer? _player;

  Phase phase = Phase.preparing;
  int index = 0;
  String message = 'Menyiapkan…';
  String heard = '';
  bool micActive = false;
  int failCount = 0; // percobaan gagal pada ayat saat ini
  int totalErrors = 0;
  int skipped = 0;
  int userAyahs = 0; // jumlah ayat yang menjadi giliran pengguna

  bool _disposed = false;
  bool _busy = false;

  // Teks terdengar (ternormalisasi) dalam satu giliran mendengar.
  String _finalText = '';
  String _partialText = '';
  String _finalRaw = '';
  String _partialRaw = '';
  int _offset = 0;

  Ayah? get current => index < ayahs.length ? ayahs[index] : null;

  bool get isSambung => mode == SessionMode.sambungAyat;

  bool isUserTurn(int i) => !isSambung || i.isOdd;

  double get progress => ayahs.isEmpty ? 0 : index / ayahs.length;

  bool get canGiveUp => failCount >= 3 && phase != Phase.finished;

  Future<void> start() async {
    userAyahs = [for (var i = 0; i < ayahs.length; i++) i]
        .where(isUserTurn)
        .length;
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
    if (isSambung) _player = AudioPlayer();
    await _advance();
  }

  void _fail(String msg) {
    phase = Phase.error;
    message = msg;
    _rec.stop();
    _notify();
  }

  /// Coba lagi setelah galat (mis. internet putus).
  Future<void> retry() async {
    if (phase != Phase.error) return;
    _resetHeard(all: true);
    await _advance();
  }

  // ---------------------------------------------------------------------------
  // Alur utama

  Future<void> _advance() async {
    if (_busy) return;
    _busy = true;
    try {
      while (!_disposed && index < ayahs.length && !isUserTurn(index)) {
        final a = ayahs[index];
        await _rec.stop();
        if (_needsBasmalah(index)) {
          phase = Phase.playing;
          message = 'Syaikh as-Sudais membaca basmalah';
          _notify();
          await _play(1, 1);
          if (_disposed) return;
        }
        phase = Phase.playing;
        message = 'Syaikh as-Sudais membaca ayat ${a.ayah}';
        _notify();
        await _play(a.surah, a.ayah);
        if (_disposed) return;
        index++;
      }
      if (_disposed) return;
      if (index >= ayahs.length) {
        await _finish();
        return;
      }
      // Giliran pengguna.
      if (isSambung && _needsBasmalah(index)) {
        phase = Phase.playing;
        message = 'Syaikh as-Sudais membaca basmalah';
        _notify();
        await _play(1, 1);
        if (_disposed) return;
      }
      _beginListening();
    } finally {
      _busy = false;
    }
  }

  bool _needsBasmalah(int i) {
    final a = ayahs[i];
    return a.ayah == 1 && a.surah != 1 && a.surah != 9;
  }

  Future<void> _play(int s, int a) async {
    final p = _player;
    if (p == null) return;
    try {
      final path = await AudioStore.instance.path(s, a);
      await p.setFilePath(path);
      final done = p.processingStateStream
          .firstWhere((st) => st == ProcessingState.completed)
          .timeout(const Duration(minutes: 5));
      unawaited(p.play());
      await done;
      await p.stop();
    } catch (_) {
      // Bila audio gagal diputar, lanjutkan saja agar sesi tidak macet.
    }
  }

  void _beginListening({bool keepLeftover = false}) {
    if (_disposed) return;
    if (!keepLeftover) _resetHeard(all: true);
    final a = current!;
    phase = Phase.listening;
    message = isSambung
        ? 'Giliran Anda: bacalah ayat ${a.ayah}'
        : 'Bacalah ayat ${a.ayah}';
    _notify();
    if (!keepLeftover || !_rec.isListening) _rec.start();
  }

  void _resetHeard({required bool all}) {
    _finalText = '';
    _partialText = '';
    _finalRaw = '';
    _partialRaw = '';
    _offset = 0;
    heard = '';
  }

  // ---------------------------------------------------------------------------
  // Pengecekan bacaan

  void _onResult(String text, bool isFinal) {
    if (_disposed) return;
    // Saat jeda singkat setelah "Benar" pada murajaah, bacaan tetap ditampung.
    if (phase != Phase.listening && !(phase == Phase.correct && !isSambung)) {
      return;
    }
    final norm = ArabicMatcher.normalize(text);
    if (isFinal) {
      _finalText += norm;
      _finalRaw = '$_finalRaw $text'.trim();
      _partialText = '';
      _partialRaw = '';
    } else {
      _partialText = norm;
      _partialRaw = text;
    }
    final raw = '$_finalRaw $_partialRaw'.trim();
    heard = raw.length > 120 ? '…${raw.substring(raw.length - 120)}' : raw;
    _notify();
    if (phase == Phase.listening) _evaluate(isFinal: isFinal);
  }

  /// Dipanggil tombol "Selesai membaca".
  void finishReading() {
    if (phase != Phase.listening) return;
    _evaluate(isFinal: true, force: true);
  }

  void _evaluate({required bool isFinal, bool force = false}) {
    final a = current;
    if (a == null) return;
    final full = _finalText + _partialText;
    final start = math.min(_offset, full.length);
    var cur = full.substring(start);
    final candidates = ArabicMatcher.candidates(a);
    final lead = ArabicMatcher.leadingExtras(cur, candidates.first);
    cur = cur.substring(lead);

    var best = MatchResult.empty;
    var minLen = 1 << 30;
    var maxLen = 0;
    for (final c in candidates) {
      final r = ArabicMatcher.matchStart(c, cur);
      if (r.similarity > best.similarity) best = r;
      minLen = math.min(minLen, c.length);
      maxLen = math.max(maxLen, c.length);
    }

    final passed = best.similarity >= threshold && (isFinal || best.tailOk);
    if (passed) {
      _offset = start + lead + best.consumed;
      _onCorrect();
      return;
    }
    if (!isFinal) return;

    final prefixSim = candidates
        .map((c) => ArabicMatcher.prefixSimilarity(c, cur))
        .reduce(math.max);
    final finishedReading = cur.length >= (minLen * 0.85).floor();
    final wrongAyah = cur.length >= 12 &&
        prefixSim < threshold - 0.2 &&
        !ArabicMatcher.looksLikeOpening(cur);
    final overshoot = cur.length > maxLen * 1.6 + 10;

    if (force || finishedReading || wrongAyah || overshoot) {
      if (force && cur.isEmpty) {
        message = 'Belum ada bacaan yang terdengar. Silakan mulai membaca.';
        _notify();
        return;
      }
      _onWrong();
    }
    // Selain itu: tunggu lanjutan bacaan (pengenal suara dimulai ulang otomatis).
  }

  void _onCorrect() {
    final a = current!;
    failCount = 0;
    phase = Phase.correct;
    message = 'Benar — ayat ${a.ayah}. Barakallahu fiik.';
    HapticFeedback.lightImpact();
    _notify();
    index++;
    if (isSambung) {
      _rec.stop();
      _resetHeard(all: true);
      Timer(const Duration(milliseconds: 700), () {
        if (!_disposed) _advance();
      });
    } else {
      if (index >= ayahs.length) {
        _finish();
        return;
      }
      // Murajaah: tetap mendengar, sisa bacaan dipakai untuk ayat berikutnya.
      Timer(const Duration(milliseconds: 500), () {
        if (_disposed || phase != Phase.correct) return;
        _beginListening(keepLeftover: true);
        _evaluate(isFinal: false);
      });
    }
  }

  void _onWrong() {
    final a = current!;
    failCount++;
    totalErrors++;
    phase = Phase.wrong;
    message = 'Bacaan ayat ${a.ayah} belum tepat. Silakan ulangi ayat ini.';
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    _rec.stop();
    _resetHeard(all: true);
    _notify();
    Timer(const Duration(milliseconds: 2500), () {
      if (_disposed || phase != Phase.wrong) return;
      _beginListening();
    });
  }

  /// Ulangi ayat saat ini dari awal (tombol "Ulangi").
  void restartAyah() {
    if (phase != Phase.listening && phase != Phase.wrong) return;
    _rec.stop();
    _resetHeard(all: true);
    _beginListening();
  }

  /// Lewati ayat saat ini (muncul setelah 3x gagal).
  Future<void> skip() async {
    if (current == null) return;
    skipped++;
    failCount = 0;
    await _rec.stop();
    _resetHeard(all: true);
    index++;
    if (isSambung) {
      await _advance();
    } else if (index >= ayahs.length) {
      await _finish();
    } else {
      _beginListening();
    }
  }

  Future<void> _finish() async {
    index = ayahs.length;
    await _rec.stop();
    phase = Phase.finished;
    message = 'Alhamdulillah, sesi selesai.';
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _rec.onResult = null;
    _rec.onFatalError = null;
    _rec.onListeningChanged = null;
    _rec.stop();
    _player?.dispose();
    super.dispose();
  }
}
