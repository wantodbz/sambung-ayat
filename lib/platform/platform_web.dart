// Versi web (PWA, untuk iPhone tanpa App Store): mikrofon lewat Web Audio,
// pengecekan bacaan dengan whisper.cpp WebAssembly, murottal diputar langsung.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import '../services/model_store.dart';
import '../services/reciters.dart';
import '../services/settings.dart';
import 'platform.dart';

SpeechEngine createSpeechEngine() => _HybridSpeech();
bool browserSpeech() => _speechJs.supported();
MurottalPlayer createMurottalPlayer() => _WebPlayer();
MurajaahIO createMurajaahIO() => _WebMurajaahIO();
const bool streamsAudio = true;

// ---------------------------------------------------------------------------
// Antarmuka JS (web/js/recorder.js & web/js/qw_bridge.js)

@JS('qwRecorder')
external _QwRecorder get _recorder;

extension type _QwRecorder._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> open();
  external void begin();
  external JSFloat32Array end();
  external void discard();
  external double level();
  external double seconds();
  external void close();
}

@JS('qwAudio')
external _QwAudio get _audio;

extension type _QwAudio._(JSObject _) implements JSObject {
  external void unlock();
  external JSPromise<JSBoolean> play(String url);
  external void stop();
}

@JS('qwSpeech')
external _QwSpeech get _speechJs;

extension type _QwSpeech._(JSObject _) implements JSObject {
  external bool supported();
  external bool start(
      String lang, JSFunction onResult, JSFunction onEnd, JSFunction onError);
  external void stop();
}

@JS('qwBridge')
external _QwBridge get _bridge;

extension type _QwBridge._(JSObject _) implements JSObject {
  external JSPromise<JSNumber> modelSize(String url);
  external JSPromise<JSBoolean> load(String url, JSFunction onProgress);
  external JSPromise<JSString> transcribe(JSFloat32Array pcm);
  external JSPromise<JSBoolean> deleteModel(String url);
  external bool supported();
}

String _modelUrl(QuranModel m) =>
    Uri.base.resolve('models/${m.fileName}').toString();

/// Muat model ke worker (dari cache browser; unduh bila belum ada).
Future<void> _ensureLoaded(QuranModel m,
    [void Function(int, int)? onProgress]) async {
  final cb = ((JSNumber r, JSNumber t) {
    onProgress?.call(r.toDartInt, t.toDartInt);
  }).toJS;
  await _bridge.load(_modelUrl(m), cb).toDart;
}

// ---------------------------------------------------------------------------
// Pemutar murottal

class _WebPlayer extends MurottalPlayer {

  @override
  void unlockFromGesture() => _audio.unlock();

  @override
  Future<void> play(int surah, int ayah) async {
    final name =
        '${surah.toString().padLeft(3, '0')}${ayah.toString().padLeft(3, '0')}.mp3';
    for (final url in Settings.instance.reciter.urlsFor(name)) {
      try {
        final ok = (await _audio.play(url).toDart).toDart;
        if (ok) return;
      } catch (_) {}
    }
  }

  @override
  Future<void> stop() async => _audio.stop();

  @override
  Future<void> dispose() async => _audio.stop();
}

// ---------------------------------------------------------------------------
// Pengenal suara Sambung Ayat: rekam satu ayat → deteksi akhir bacaan
// (hening) → periksa dengan model → hasil "final".

class _WhisperSpeech extends SpeechEngine {
  bool _wanted = false;
  bool _capturing = false;
  int _gen = 0;
  int _session = 0;
  Timer? _poll;
  Future<JSBoolean>? _opening;

  // Deteksi suara
  double _floor = 1;
  int _ticks = 0;
  int _loudTicks = 0;
  int _quietTicks = 0;
  bool _speechStarted = false;

  @override
  bool get isListening => _capturing;

  @override
  bool get supportsFlush => true;

  @override
  Future<void> prepareFromGesture() async {
    _opening ??= _recorder.open().toDart;
    await _opening;
  }

  @override
  Future<bool> init() async {
    if (!_bridge.supported()) {
      onFatalError?.call('Browser ini belum mendukung model pengecek bacaan '
          '(perlu iOS 16.4 atau lebih baru).');
      return false;
    }
    try {
      await prepareFromGesture();
    } catch (e) {
      _opening = null; // agar bisa dicoba lagi
      onFatalError?.call('Mikrofon tidak bisa dibuka ($e). Pastikan izin '
          'mikrofon diberikan: Pengaturan iPhone → Safari → Mikrofon → Izinkan, '
          'lalu ketuk "Coba lagi".');
      return false;
    }
    final m = Settings.instance.model;
    final had = await _bridge.modelSize(_modelUrl(m)).toDart;
    if (had.toDartInt <= 0) {
      onFatalError?.call('Model pengecek belum diunduh. Buka Pengaturan (⚙) '
          'di halaman utama, unduh model ${m.label}, lalu coba lagi.');
      return false;
    }
    try {
      await _ensureLoaded(m);
      return true;
    } catch (e) {
      onFatalError?.call('Model pengecek gagal dimuat ($e).');
      return false;
    }
  }

  @override
  Future<void> start() async {
    _wanted = true;
    _gen++;
    _begin();
  }

  void _begin() {
    if (!_wanted) return;
    _recorder.begin();
    _capturing = true;
    _ticks = 0;
    _loudTicks = 0;
    _quietTicks = 0;
    _speechStarted = false;
    _floor = 1;
    onListeningChanged?.call(true);
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void _tick() {
    if (!_capturing) return;
    final lv = _recorder.level();
    _ticks++;
    if (_ticks <= 6) {
      if (lv < _floor) _floor = lv;
      return;
    }
    final thr = (_floor + 0.15).clamp(0.3, 0.8);
    if (lv > thr) {
      onSound?.call();
      _loudTicks++;
      _quietTicks = 0;
      if (_loudTicks >= 3) {
        _speechStarted = true;
        onActivity?.call();
      }
    } else {
      _quietTicks++;
    }
    final secs = _recorder.seconds();
    if ((_speechStarted && _quietTicks >= 12) || secs > 45) {
      flush();
    } else if (!_speechStarted && secs > 20) {
      // Belum ada bacaan: buang dan dengarkan ulang tanpa memeriksa.
      _recorder.discard();
      _capturing = false;
      _begin();
    }
  }

  @override
  void flush() {
    if (!_capturing) return;
    _poll?.cancel();
    _capturing = false;
    final pcm = _recorder.end().toDart;
    onListeningChanged?.call(false);
    _process(pcm, _gen, ++_session);
  }

  Future<void> _process(Float32List pcm, int gen, int session) async {
    if (pcm.length < 16000 * 0.4) {
      if (gen == _gen && _wanted) _begin();
      return;
    }
    onProcessingChanged?.call(true);
    String text = '';
    try {
      text = (await _bridge.transcribe(pcm.toJS).toDart).toDart;
    } catch (e) {
      onProcessingChanged?.call(false);
      if (gen == _gen) onFatalError?.call('Pemeriksaan gagal: $e');
      return;
    }
    onProcessingChanged?.call(false);
    if (gen != _gen || !_wanted) return;
    onResult?.call(text, true, session);
    // Bila sesi masih menunggu bacaan (belum benar/salah), dengarkan lagi.
    if (gen == _gen && _wanted && !_capturing) _begin();
  }

  @override
  Future<void> stop() async {
    _wanted = false;
    _gen++;
    _poll?.cancel();
    if (_capturing) _recorder.discard();
    _capturing = false;
    onListeningChanged?.call(false);
  }
}

// ---------------------------------------------------------------------------
// Pengenal suara bawaan Safari (tanpa unduh model).

class _SafariSpeech extends SpeechEngine {
  bool _wanted = false;
  bool _listening = false;
  int _gen = 0;
  int _session = 0;
  int _emptyEnds = 0;
  bool _gotResult = false;

  /// Dipanggil bila Safari menolak/tidak mendukung pengenalan suara.
  void Function(String code)? onUnavailable;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> init() async => _speechJs.supported();

  @override
  Future<void> start() async {
    _wanted = true;
    _gen++;
    _emptyEnds = 0;
    _listen();
  }

  void _listen() {
    if (!_wanted) return;
    final gen = _gen;
    final session = ++_session;
    _gotResult = false;
    final onRes = ((JSString t, JSBoolean f) {
      if (gen != _gen) return;
      _gotResult = true;
      _emptyEnds = 0;
      onResult?.call(t.toDart, f.toDart, session);
    }).toJS;
    final onEnd = (() {
      if (gen != _gen) return;
      _listening = false;
      onListeningChanged?.call(false);
      if (!_gotResult) _emptyEnds++;
      if (_emptyEnds >= 6) {
        // Berulang kali berhenti tanpa hasil: anggap tidak berfungsi.
        _wanted = false;
        onUnavailable?.call('no-result');
        return;
      }
      if (_wanted) Timer(const Duration(milliseconds: 250), _listen);
    }).toJS;
    final onErr = ((JSString code) {
      if (gen != _gen) return;
      final c = code.toDart;
      if (c == 'not-allowed' ||
          c == 'service-not-allowed' ||
          c == 'audio-capture' ||
          c == 'language-not-supported' ||
          c == 'start-failed') {
        _wanted = false;
        _gen++;
        _listening = false;
        _speechJs.stop();
        onUnavailable?.call(c);
      } else if (c == 'network') {
        _wanted = false;
        onFatalError?.call('Pengenal suara Safari membutuhkan internet. '
            'Periksa koneksi lalu ketuk "Coba lagi".');
      }
      // 'no-speech', 'aborted', dll.: onend akan memulai ulang.
    }).toJS;
    if (_speechJs.start('ar-SA', onRes, onEnd, onErr)) {
      _listening = true;
      onListeningChanged?.call(true);
    }
  }

  @override
  Future<void> stop() async {
    _wanted = false;
    _gen++;
    _speechJs.stop();
    _listening = false;
    onListeningChanged?.call(false);
  }
}

/// Jalan tengah: pakai pengenal suara Safari bila tersedia; bila tidak,
/// pindah ke model pengecek bacaan (whisper).
class _HybridSpeech extends SpeechEngine {
  final _SafariSpeech _safari = _SafariSpeech();
  final _WhisperSpeech _whisper = _WhisperSpeech();
  late SpeechEngine _active =
      _speechJs.supported() ? _safari : _whisper;

  _HybridSpeech() {
    for (final e in [_safari, _whisper]) {
      e.onResult = (t, f, s) {
        if (identical(e, _active)) onResult?.call(t, f, s);
      };
      e.onFatalError = (m) {
        if (identical(e, _active)) onFatalError?.call(m);
      };
      e.onListeningChanged = (l) {
        if (identical(e, _active)) onListeningChanged?.call(l);
      };
      e.onProcessingChanged = (p) {
        if (identical(e, _active)) onProcessingChanged?.call(p);
      };
      e.onActivity = () {
        if (identical(e, _active)) onActivity?.call();
      };
      e.onSound = () {
        if (identical(e, _active)) onSound?.call();
      };
    }
    _safari.onUnavailable = _fallback;
  }

  Future<void> _fallback(String code) async {
    _active = _whisper;
    onListeningChanged?.call(false);
    final hasModel = await murajaahIO.hasModel(Settings.instance.model);
    onFatalError?.call(hasModel
        ? 'Pengenal suara Safari tidak bisa dipakai di iPhone ini ($code). '
            'Ketuk "Coba lagi" untuk memakai model pengecek bacaan.'
        : 'Pengenal suara Safari tidak bisa dipakai di iPhone ini ($code). '
            'Buka Pengaturan (⚙) di halaman utama, unduh model pengecek, '
            'lalu coba lagi.');
  }

  @override
  bool get isListening => _active.isListening;

  @override
  bool get supportsFlush => _active.supportsFlush;

  @override
  void flush() => _active.flush();

  @override
  Future<void> prepareFromGesture() => _active.prepareFromGesture();

  @override
  Future<bool> init() => _active.init();

  @override
  Future<void> start() => _active.start();

  @override
  Future<void> stop() async {
    await _safari.stop();
    await _whisper.stop();
  }
}

// ---------------------------------------------------------------------------
// Murajaah

class _WebMurajaahIO extends MurajaahIO {
  Future<JSBoolean>? _opening;
  String? lastError;

  @override
  Future<bool> hasModel(QuranModel m) async => await modelSize(m) > 0;

  @override
  Future<int> modelSize(QuranModel m) async {
    try {
      return (await _bridge.modelSize(_modelUrl(m)).toDart).toDartInt;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> downloadModel(QuranModel m,
      {void Function(int, int)? onProgress, bool Function()? isCancelled}) {
    if (!_bridge.supported()) {
      throw Exception('Browser/iOS ini belum mendukung model pengecek. '
          'Diperlukan iOS 16.4 atau lebih baru.');
    }
    return _ensureLoaded(m, onProgress);
  }

  @override
  Future<void> deleteModel(QuranModel m) async {
    await _bridge.deleteModel(_modelUrl(m)).toDart;
  }

  @override
  bool get needsGesture => true;

  @override
  Future<bool> openRecorder() async {
    try {
      _opening ??= _recorder.open().toDart;
      await _opening;
      return true;
    } catch (e) {
      _opening = null;
      lastError = '$e';
      return false;
    }
  }

  @override
  Future<void> startRecording() async => _recorder.begin();

  @override
  double get level => _recorder.level();

  @override
  Future<Float32List?> stopRecording() async => _recorder.end().toDart;

  @override
  Future<void> discardRecording() async => _recorder.discard();

  @override
  Future<void> closeRecorder() async {
    _recorder.discard();
  }

  @override
  Stream<TxEvent> transcribe(QuranModel m, List<Float32List> chunks) async* {
    try {
      await _ensureLoaded(m);
    } catch (e) {
      yield TxEvent(0, chunks.length, '', error: '$e');
      return;
    }
    for (var i = 0; i < chunks.length; i++) {
      String text;
      try {
        text = (await _bridge.transcribe(chunks[i].toJS).toDart).toDart;
      } catch (e) {
        yield TxEvent(i, chunks.length, '', error: '$e');
        return;
      }
      yield TxEvent(i + 1, chunks.length, text);
    }
    yield TxEvent(chunks.length, chunks.length, '', finished: true);
  }

  @override
  Future<void> cleanup() async {}
}
