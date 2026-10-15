import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Pembungkus pengenal suara Android (bahasa Arab) yang bisa "mendengar
/// terus": bila sistem berhenti karena jeda, ia otomatis dimulai lagi.
class Recognizer {
  Recognizer._();
  static final Recognizer instance = Recognizer._();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _available = false;
  String? _localeId;

  /// Dipanggil setiap ada hasil: (teks, final?, nomor sesi dengar).
  /// Nomor sesi naik setiap kali pengenal suara dimulai ulang setelah jeda.
  void Function(String text, bool isFinal, int session)? onResult;

  int _session = 0;

  /// Dipanggil bila terjadi galat yang perlu diketahui pengguna.
  void Function(String message)? onFatalError;

  /// Dipanggil saat status mendengar berubah.
  void Function(bool listening)? onListeningChanged;

  bool _wanted = false; // apakah sesi ingin terus mendengar
  bool _restartScheduled = false;
  int _generation = 0;

  bool get available => _available;
  bool get isListening => _speech.isListening;

  Future<bool> init() async {
    if (_initialized) return _available;
    _available = await _speech.initialize(
      onStatus: _onStatus,
      onError: _onError,
      debugLogging: false,
    );
    _initialized = true;
    if (_available) {
      try {
        final locales = await _speech.locales();
        String? pick(bool Function(String id) test) {
          for (final l in locales) {
            if (test(l.localeId.toLowerCase())) return l.localeId;
          }
          return null;
        }

        _localeId = pick((id) => id == 'ar_sa' || id == 'ar-sa') ??
            pick((id) => id.startsWith('ar')) ??
            'ar-SA';
      } catch (_) {
        _localeId = 'ar-SA';
      }
    }
    return _available;
  }

  /// Mulai mendengar terus-menerus sampai [stop] dipanggil.
  Future<void> start() async {
    _wanted = true;
    _generation++;
    await _listen();
  }

  /// Hentikan mendengar dan buang hasil yang belum final.
  Future<void> stop() async {
    _wanted = false;
    _generation++;
    try {
      await _speech.cancel();
    } catch (_) {}
    onListeningChanged?.call(false);
  }

  Future<void> _listen() async {
    if (!_wanted || !_available) return;
    if (_speech.isListening) return;
    final gen = _generation;
    final session = ++_session;
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult r) {
          if (gen != _generation || !_wanted) return;
          onResult?.call(r.recognizedWords, r.finalResult, session);
        },
        localeId: _localeId,
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 6),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
      );
      onListeningChanged?.call(true);
    } catch (_) {
      _scheduleRestart(const Duration(milliseconds: 800));
    }
  }

  void _scheduleRestart(Duration delay) {
    if (!_wanted || _restartScheduled) return;
    _restartScheduled = true;
    final gen = _generation;
    Timer(delay, () {
      _restartScheduled = false;
      if (gen != _generation) return;
      _listen();
    });
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      onListeningChanged?.call(false);
      _scheduleRestart(const Duration(milliseconds: 300));
    } else if (status == SpeechToText.listeningStatus) {
      onListeningChanged?.call(true);
    }
  }

  void _onError(SpeechRecognitionError e) {
    final msg = e.errorMsg;
    if (msg.contains('network') || msg.contains('server')) {
      _wanted = false;
      onFatalError?.call(
          'Pengenal suara membutuhkan koneksi internet. Periksa koneksi Anda lalu ketuk "Coba lagi".');
      return;
    }
    if (msg.contains('permission') || msg.contains('insufficient')) {
      _wanted = false;
      onFatalError
          ?.call('Izin mikrofon belum diberikan. Aktifkan di Pengaturan HP.');
      return;
    }
    // error_no_match, error_speech_timeout, error_busy, error_client, dll.
    _scheduleRestart(Duration(milliseconds: msg.contains('busy') ? 900 : 400));
  }
}
