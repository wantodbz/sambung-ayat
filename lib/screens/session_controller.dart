import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/quran.dart';
import '../platform/platform.dart';
import '../services/matcher.dart';
import '../services/parent_report.dart';
import '../services/reciters.dart';
import '../services/settings.dart';

enum SessionMode { sambungAyat, murajaah }

enum Phase { preparing, playing, listening, correct, wrong, finished, error }

/// Mengatur jalannya satu sesi Sambung Ayat:
/// HP membaca ayat ke-1, pengguna ayat ke-2, HP ayat ke-3, dan seterusnya.
///
/// Bacaan yang salah atau tidak terbaca dicatat lalu sesi tetap berlanjut;
/// koreksinya ditampilkan di akhir. Pada giliran pengguna berjalan hitung
/// mundur [waitSeconds] detik sampai suara bacaan pertama terdengar; bila
/// habis sebelum ada suara, ayat dicatat tidak terbaca. Setelah suara
/// terdengar, hitung mundur hilang; bila bacaan belum dinilai benar dan
/// pengguna diam [quietSeconds] detik (tanpa ditampilkan), bacaan langsung
/// dinilai (salah/tidak selesai) dan sesi lanjut ke ayat berikutnya.
///
/// (Menu Murajaah memakai MurajaahController tersendiri.)
class SessionController extends ChangeNotifier {
  SessionController({
    required this.mode,
    required this.ayahs,
    required this.threshold,
    required this.title,
    SpeechEngine? engine,
    MurottalPlayer? player,
    this.waitSeconds = 15,
    this.quietSeconds = 3,
  })  : _engine = engine,
        _player = player;

  final SessionMode mode;
  final List<Ayah> ayahs;
  final double threshold;
  final String title;

  /// Batas menunggu sebelum suara bacaan pertama terdengar (detik).
  final int waitSeconds;

  /// Lama diam setelah membaca sebelum lanjut otomatis (detik, tidak tampil).
  final int quietSeconds;

  final SpeechEngine? _engine;
  SpeechEngine get _rec => _engine ?? speechEngine;
  MurottalPlayer? _player;

  /// Versi web: sesi harus dimulai dari ketukan pengguna (aturan iPhone).
  static bool get needsGesture => streamsAudio;

  /// Versi web: bacaan sedang diperiksa model.
  bool processing = false;
  bool _forceNext = false;

  Phase phase = Phase.preparing;
  int index = 0;
  String message = 'Menyiapkan…';
  String heard = '';
  bool micActive = false;

  /// Sisa detik hitung mundur pada giliran pengguna.
  int countdown = 0;

  /// Suara bacaan sudah terdengar pada giliran ini (hitung mundur hilang).
  bool voiceHeard = false;
  Timer? _countdownTimer;
  int _silentTicks = 0; // sebelum ada suara (hitung mundur 15 detik)
  int _quietTicks = 0; // diam setelah ada suara (3 detik, tidak tampil)
  String _lastPartialSeen = '';
  static const int _ticksPerSecond = 4;

  /// Hasil tiap ayat yang menjadi giliran pengguna, berurutan.
  final List<AyahVerdict> verdicts = [];

  /// Surat yang tercatat di laporan orang tua.
  List<int> recordedSurahs = [];

  bool _disposed = false;
  bool _busy = false;
  int _turn = 0; // naik setiap pergantian giliran; menahan timer usang

  // Teks terdengar (ternormalisasi) dalam satu giliran.
  String _finalText = '';
  String _partialText = '';
  String _finalRaw = '';
  String _partialRaw = '';
  int _session = -1;

  static String _key(Ayah a) => '${a.surah}:${a.ayah}';

  Ayah? get current => index < ayahs.length ? ayahs[index] : null;

  bool get isSambung => mode == SessionMode.sambungAyat;

  bool isUserTurn(int i) => !isSambung || i.isOdd;

  double get progress => ayahs.isEmpty ? 0 : index / ayahs.length;

  /// Jumlah ayat yang menjadi giliran pengguna.
  int get userAyahs =>
      [for (var i = 0; i < ayahs.length; i++) i].where(isUserTurn).length;

  List<AyahVerdict> get mistakes =>
      verdicts.where((v) => v.verdict != Verdict.correct).toList();

  int get correctCount =>
      verdicts.where((v) => v.verdict == Verdict.correct).length;

  Reciter get _reciter => Settings.instance.reciter;

  // ---------------------------------------------------------------------------
  // Mulai, ulang, galat

  Future<void> start() async {
    final rec = _rec;
    rec.onResult = _onResult;
    rec.onFatalError = _fail;
    rec.onListeningChanged = (l) {
      micActive = l;
      _notify();
    };
    rec.onProcessingChanged = (p) {
      processing = p;
      if (p) _silentTicks = 0;
      _notify();
    };
    rec.onActivity = _markVoice;
    rec.onSound = _noteSound;
    if (isSambung) _player ??= createMurottalPlayer();
    phase = Phase.preparing;
    message = 'Menyiapkan…';
    _notify();
    final ok = await rec.init();
    if (_disposed) return;
    if (!ok) {
      if (phase != Phase.error) {
        _fail('Pengenal suara tidak tersedia di HP ini. Pastikan aplikasi '
            'Google terpasang dan izin mikrofon diberikan.');
      }
      return;
    }
    await _advance();
  }

  /// Versi web: dipanggil langsung dari ketukan tombol "Mulai".
  Future<void> startFromGesture() async {
    if (isSambung) {
      _player ??= createMurottalPlayer();
      _player!.unlockFromGesture();
    }
    final prep = _rec.prepareFromGesture(); // sinkron di dalam ketukan
    await start();
    await prep.catchError((_) {});
  }

  /// Ulangi seluruh sesi dari awal (layar hasil).
  Future<void> restartSession() async {
    _turn++;
    _stopCountdown();
    index = 0;
    verdicts.clear();
    recordedSurahs = [];
    _resetHeard();
    await startFromGesture();
  }

  void _fail(String msg) {
    _stopCountdown();
    phase = Phase.error;
    message = msg;
    _rec.stop();
    _notify();
  }

  /// Coba lagi setelah galat (mis. internet putus).
  Future<void> retry() async {
    if (phase != Phase.error) return;
    // Versi web: ketukan "Coba lagi" juga membuka mikrofon (aturan iPhone).
    final prep = _rec.prepareFromGesture();
    _resetHeard();
    phase = Phase.preparing;
    message = 'Menyiapkan…';
    _notify();
    await prep.catchError((_) {});
    final ok = await _rec.init();
    if (_disposed) return;
    if (!ok) {
      if (phase != Phase.error) _fail('Pengecek bacaan belum siap.');
      return;
    }
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
          message = '${_reciter.short} membaca basmalah';
          _notify();
          await _play(1, 1);
          if (_disposed) return;
        }
        phase = Phase.playing;
        message = '${_reciter.short} membaca ayat ${a.ayah}';
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
        message = '${_reciter.short} membaca basmalah';
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
    try {
      await _player?.play(s, a);
    } catch (_) {
      // Audio gagal diputar: lanjutkan agar sesi tidak macet.
    }
  }

  void _beginListening() {
    if (_disposed) return;
    _resetHeard();
    final a = current!;
    phase = Phase.listening;
    message = 'Giliran Anda: bacalah ayat ${a.ayah}';
    voiceHeard = false;
    _armCountdown();
    _notify();
    _rec.start();
  }

  void _resetHeard() {
    _lastPartialSeen = '';
    _finalText = '';
    _partialText = '';
    _finalRaw = '';
    _partialRaw = '';
    heard = '';
  }

  // ---------------------------------------------------------------------------
  // Hitung mundur

  void _armCountdown() {
    _countdownTimer?.cancel();
    _silentTicks = 0;
    _quietTicks = 0;
    countdown = waitSeconds;
    _countdownTimer = Timer.periodic(
        const Duration(milliseconds: 1000 ~/ _ticksPerSecond), (_) {
      if (_disposed || phase != Phase.listening) return;
      if (voiceHeard) {
        // Setelah ada suara: hitung diam (tidak ditampilkan).
        if (processing) {
          _quietTicks = 0; // sedang diperiksa: jangan dihitung
          return;
        }
        _quietTicks++;
        if (_quietTicks >= quietSeconds * _ticksPerSecond) {
          _onQuietAfterSpeech();
        }
        return;
      }
      if (processing) {
        _silentTicks = 0; // sedang diperiksa: jangan dihitung
      } else {
        _silentTicks++;
      }
      final left = waitSeconds - _silentTicks / _ticksPerSecond;
      final shown = left.ceil().clamp(0, waitSeconds);
      if (shown != countdown) {
        countdown = shown;
        _notify();
      }
      if (left <= 0) _onTimeout();
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  /// Suara bacaan pertama terdengar: hitung mundur disembunyikan; mulai
  /// sekarang yang dihitung adalah lama diam (tanpa tampilan).
  void _markVoice() {
    if (_disposed || voiceHeard || phase != Phase.listening) return;
    voiceHeard = true;
    _quietTicks = 0;
    _notify();
  }

  /// Masih terdengar suara bacaan: hitungan diam dimulai lagi.
  void _noteSound() {
    if (voiceHeard) _quietTicks = 0;
  }

  /// Sudah membaca lalu diam [quietSeconds] detik tanpa dinilai benar:
  /// nilai sekarang (salah/tidak selesai) lalu lanjut.
  void _onQuietAfterSpeech() {
    _stopCountdown();
    final a = current;
    if (a == null) return;
    if (_currentHeard().isEmpty) {
      _recordNotRead(a);
    } else {
      _evaluate(isFinal: true, force: true);
    }
  }

  /// Waktu tunggu habis sebelum ada suara bacaan.
  void _onTimeout() {
    _stopCountdown();
    final a = current;
    if (a == null) return;
    if (_currentHeard().isEmpty) {
      _recordNotRead(a, timeout: true);
    } else {
      _evaluate(isFinal: true, force: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Pengecekan bacaan

  void _onResult(String text, bool isFinal, int session) {
    if (_disposed || phase != Phase.listening) return;
    // Hasil terlambat dari sesi dengar lama (sudah disimpan) diabaikan.
    if (session < _session) return;
    // Sesi dengar baru tanpa hasil final sesi lama: simpan hasil sementaranya.
    if (session != _session) {
      if (_partialText.isNotEmpty) {
        _finalText += _partialText;
        _finalRaw = '$_finalRaw $_partialRaw'.trim();
      }
      _partialText = '';
      _partialRaw = '';
      _session = session;
    }
    final norm = ArabicMatcher.normalize(text);
    // Ada bacaan terdengar: hitung mundur disembunyikan.
    if (text.trim().isNotEmpty) {
      _markVoice();
      // Hasil sementara yang bertambah berarti masih membaca.
      if (!isFinal && text != _lastPartialSeen) {
        _lastPartialSeen = text;
        _quietTicks = 0;
      }
    }
    if (isFinal) {
      // Sebagian HP mengirim hasil final kosong/terpotong; pakai yang lebih lengkap.
      final useFinal = norm.length >= _partialText.length * 0.6;
      _finalText += useFinal ? norm : _partialText;
      _finalRaw = '$_finalRaw ${useFinal ? text : _partialRaw}'.trim();
      _partialText = '';
      _partialRaw = '';
    } else {
      _partialText = norm;
      _partialRaw = text;
    }
    final raw = '$_finalRaw $_partialRaw'.trim();
    heard = raw.length > 120 ? '…${raw.substring(raw.length - 120)}' : raw;
    _notify();
    final force = isFinal && _forceNext;
    if (isFinal) _forceNext = false;
    _evaluate(isFinal: isFinal, force: force);
  }

  /// Tombol "Selesai membaca": nilai bacaan sekarang juga.
  void finishReading() {
    if (phase != Phase.listening) return;
    if (_rec.supportsFlush && _rec.isListening) {
      // Versi web: periksa potongan rekaman sekarang, lalu nilai.
      _forceNext = true;
      _rec.flush();
      return;
    }
    _evaluate(isFinal: true, force: true);
  }

  /// Bacaan terdengar (ternormalisasi) tanpa ta'awudz/basmalah di awal.
  String _currentHeard() {
    final a = current;
    if (a == null) return '';
    final cur = _finalText + _partialText;
    final lead =
        ArabicMatcher.leadingExtras(cur, ArabicMatcher.candidates(a).first);
    return cur.substring(lead);
  }

  void _evaluate({required bool isFinal, bool force = false}) {
    if (phase != Phase.listening) return;
    final a = current;
    if (a == null) return;
    final cur = _currentHeard();
    final candidates = ArabicMatcher.candidates(a);

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
      _onCorrect(a, best.similarity);
      return;
    }
    if (!isFinal) return;

    final prefixSim = cur.isEmpty
        ? 1.0
        : candidates
            .map((c) => ArabicMatcher.prefixSimilarity(c, cur))
            .reduce(math.max);
    final finishedReading = cur.length >= (minLen * 0.85).floor();
    final wrongAyah = cur.length >= 12 &&
        prefixSim < threshold - 0.2 &&
        !ArabicMatcher.looksLikeOpening(cur);
    final overshoot = cur.length > maxLen * 1.6 + 10;

    if (force || finishedReading || wrongAyah || overshoot) {
      if (cur.isEmpty) {
        // "Selesai membaca" diketuk tanpa bacaan apa pun.
        _recordNotRead(a);
        return;
      }
      _onWrong(a, cur, best.similarity);
    }
    // Selain itu: tunggu lanjutan bacaan (pengenal suara dimulai ulang otomatis).
  }

  void _onCorrect(Ayah a, double similarity) {
    verdicts.add(AyahVerdict(a, Verdict.correct, similarity));
    phase = Phase.correct;
    message = 'Benar — ayat ${a.ayah}. Barakallahu fiik.';
    _haptic(strong: false);
    _next(const Duration(milliseconds: 700));
  }

  void _onWrong(Ayah a, String cur, double similarity) {
    Set<int> wrong = const {};
    try {
      wrong = ArabicMatcher.wrongChars(a.text, cur, 0, 6, cur.length);
    } catch (_) {}
    verdicts.add(AyahVerdict(a, Verdict.wrong, similarity, wrong));
    phase = Phase.wrong;
    message = 'Ayat ${a.ayah} dicatat untuk dikoreksi di akhir. Lanjut…';
    _haptic(strong: true);
    _next(const Duration(milliseconds: 1500));
  }

  void _recordNotRead(Ayah a, {bool timeout = false}) {
    verdicts.add(AyahVerdict(a, Verdict.notRead, 0));
    phase = Phase.wrong;
    message = timeout
        ? 'Waktu habis — ayat ${a.ayah} dicatat tidak terbaca. Lanjut…'
        : 'Ayat ${a.ayah} dicatat tidak terbaca. Lanjut…';
    _haptic(strong: true);
    _next(const Duration(milliseconds: 1500));
  }

  /// Tutup giliran ini lalu lanjut ke ayat berikutnya setelah [delay].
  void _next(Duration delay) {
    _stopCountdown();
    _rec.stop();
    _resetHeard();
    _notify();
    index++;
    final turn = ++_turn;
    Timer(delay, () {
      if (_disposed || turn != _turn) return;
      _advance();
    });
  }

  /// Ulangi bacaan ayat saat ini dari awal (tombol "Ulangi"), sebelum dinilai.
  void restartAyah() {
    if (phase != Phase.listening) return;
    _rec.stop();
    _beginListening();
  }

  Future<void> _finish() async {
    _stopCountdown();
    index = ayahs.length;
    await _rec.stop();
    final failed = {
      for (final v in verdicts)
        if (v.verdict != Verdict.correct) _key(v.ayah)
    };
    try {
      recordedSurahs = await ParentReport.instance.recordSession(
        ayahs: ayahs,
        mode: isSambung ? 'Sambung Ayat' : 'Murajaah',
        failed: (a) => failed.contains(_key(a)),
        errorsOf: (_) => 0,
      );
    } catch (_) {
      recordedSurahs = [];
    }
    if (_disposed) return;
    phase = Phase.finished;
    message = failed.isEmpty
        ? 'Masya Allah, semua bacaan benar!'
        : '${failed.length} ayat perlu diperbaiki';
    _haptic(strong: failed.isNotEmpty);
    _notify();
  }

  void _haptic({required bool strong}) {
    try {
      final f = strong
          ? HapticFeedback.mediumImpact()
          : HapticFeedback.lightImpact();
      f.catchError((_) {});
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _turn++;
    _stopCountdown();
    final rec = _rec;
    rec.onResult = null;
    rec.onFatalError = null;
    rec.onListeningChanged = null;
    rec.onProcessingChanged = null;
    rec.onActivity = null;
    rec.onSound = null;
    rec.stop();
    _player?.dispose();
    super.dispose();
  }
}
