import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quran_whisper/quran_whisper.dart';
import 'package:record/record.dart';

import '../services/audio_store.dart';
import '../services/model_store.dart';
import '../services/recognizer.dart';
import '../services/wav.dart';
import 'platform.dart';

SpeechEngine createSpeechEngine() => Recognizer.instance;
MurottalPlayer createMurottalPlayer() => _NativePlayer();
MurajaahIO createMurajaahIO() => _NativeMurajaahIO();
const bool streamsAudio = false;
bool browserSpeech() => false;

const _screen = MethodChannel('sambung_ayat/layar');

Future<void> keepScreenOn(bool on) async {
  try {
    await _screen.invokeMethod<void>('tetapNyala', on);
  } catch (_) {}
}

class _NativePlayer extends MurottalPlayer {
  final AudioPlayer _p = AudioPlayer();

  @override
  Future<void> play(int surah, int ayah) async {
    try {
      final path = await AudioStore.instance.path(surah, ayah);
      await _p.setFilePath(path);
      final done = _p.processingStateStream
          .firstWhere((st) => st == ProcessingState.completed)
          .timeout(const Duration(minutes: 5));
      unawaited(_p.play());
      await done;
      await _p.stop();
    } catch (_) {
      // Bila audio gagal diputar, lanjutkan saja agar sesi tidak macet.
    }
  }

  @override
  Future<void> stop() => _p.stop();

  @override
  Future<void> dispose() => _p.dispose();
}

class _NativeMurajaahIO extends MurajaahIO {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amp;
  double _level = 0;

  // Rekaman langsung (PCM) untuk pemeriksaan sambil membaca.
  StreamSubscription<Uint8List>? _pcmSub;
  Completer<void>? _pcmDone;
  int? _oddByte; // sisa 1 bita bila blok rekaman berukuran ganjil

  @override
  bool get supportsLive => true;

  @override
  Future<void> startLiveRecording(
      void Function(Int16List samples) onSamples) async {
    await _deleteRec(); // sisa berkas versi lama
    await _pcmSub?.cancel();
    _oddByte = null;
    final done = _pcmDone = Completer<void>();
    final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1));
    _pcmSub = stream.listen((bytes) {
      final s = _toInt16(bytes);
      if (s.isEmpty) return;
      _level = _levelOf(s);
      onSamples(s);
    }, onDone: () {
      if (!done.isCompleted) done.complete();
    }, onError: (Object _) {
      if (!done.isCompleted) done.complete();
    });
  }

  @override
  Future<void> stopLiveRecording() async {
    try {
      await _recorder.stop();
    } catch (_) {}
    await _pcmDone?.future
        .timeout(const Duration(seconds: 2), onTimeout: () {});
    await _pcmSub?.cancel();
    _pcmSub = null;
    _level = 0;
  }

  /// PCM 16-bit little-endian → sampel.
  Int16List _toInt16(Uint8List bytes) {
    final carry = _oddByte;
    final total = bytes.length + (carry == null ? 0 : 1);
    final n = total ~/ 2;
    final out = Int16List(n);
    int at(int i) => carry == null ? bytes[i] : (i == 0 ? carry : bytes[i - 1]);
    for (var i = 0; i < n; i++) {
      final v = at(2 * i) | (at(2 * i + 1) << 8);
      out[i] = v >= 0x8000 ? v - 0x10000 : v;
    }
    _oddByte = total.isOdd ? at(total - 1) : null;
    return out;
  }

  static double _levelOf(Int16List s) {
    var sum = 0.0;
    for (final v in s) {
      sum += v * v;
    }
    final rms = math.sqrt(sum / s.length) / 32768.0;
    final db = rms > 0 ? 20 * math.log(rms) / math.ln10 : -100.0;
    return ((db + 50) / 50).clamp(0.0, 1.0);
  }

  @override
  Future<LiveTranscriber> openLiveTranscriber(QuranModel m) async {
    final threads = math.min(4, math.max(2, Platform.numberOfProcessors));
    return _NativeLiveTranscriber(WhisperSession.start(
      modelPath: await ModelStore.instance.path(m),
      threads: threads,
      library: await whisperLibrary(),
    ));
  }

  static Future<String> _recPath() async =>
      '${(await getTemporaryDirectory()).path}/murajaah.wav';

  Future<void> _deleteRec() async {
    try {
      final f = File(await _recPath());
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  @override
  Future<bool> hasModel(QuranModel m) => ModelStore.instance.has(m);

  @override
  Future<int> modelSize(QuranModel m) => ModelStore.instance.size(m);

  @override
  Future<void> downloadModel(QuranModel m,
          {void Function(int, int)? onProgress, bool Function()? isCancelled}) =>
      ModelStore.instance
          .download(m, onProgress: onProgress, isCancelled: isCancelled);

  @override
  Future<void> deleteModel(QuranModel m) => ModelStore.instance.delete(m);

  @override
  bool get needsGesture => false;

  @override
  Future<bool> openRecorder() => _recorder.hasPermission();

  @override
  Future<void> startRecording() async {
    await _deleteRec();
    await _recorder.start(
      const RecordConfig(
          encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: await _recPath(),
    );
    await _amp?.cancel();
    _amp = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 150))
        .listen((a) => _level = ((a.current + 50) / 50).clamp(0.0, 1.0));
  }

  @override
  double get level => _level;

  @override
  Future<Float32List?> stopRecording() async {
    await _amp?.cancel();
    _amp = null;
    _level = 0;
    final path = await _recorder.stop() ?? await _recPath();
    try {
      return await readWavMono(path);
    } finally {
      // Suara sudah di memori: berkas rekaman langsung dihapus.
      await _deleteRec();
    }
  }

  @override
  Future<void> discardRecording() async {
    await _amp?.cancel();
    _amp = null;
    await _pcmSub?.cancel();
    _pcmSub = null;
    _level = 0;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
    await _deleteRec();
  }

  @override
  Future<void> closeRecorder() async {
    await discardRecording();
  }

  @override
  Stream<TxEvent> transcribe(QuranModel m, List<Float32List> chunks) async* {
    final modelPath = await ModelStore.instance.path(m);
    final threads = math.min(4, math.max(2, Platform.numberOfProcessors));
    await for (final ev in QuranWhisper.transcribe(
        modelPath: modelPath, chunks: chunks, threads: threads)) {
      yield TxEvent(ev.done, ev.total, ev.text,
          error: ev.error, finished: ev.finished);
    }
  }

  @override
  Future<void> cleanup() async {
    await _deleteRec();
    await ModelStore.instance.cleanupPartial();
  }
}

class _NativeLiveTranscriber extends LiveTranscriber {
  _NativeLiveTranscriber(this._s);
  final WhisperSession _s;

  @override
  Stream<TxEvent> get events => _s.events.map((e) =>
      TxEvent(e.done, e.total, e.text, error: e.error, finished: e.finished));

  @override
  int get submitted => _s.submitted;

  @override
  void add(Int16List chunk) {
    final sec = chunk.length / 16000;
    _s.add(chunk, maxTokens: maxTokensFor(sec), audioCtx: audioCtxFor(sec));
  }

  @override
  void close() => _s.close();

  @override
  Future<void> cancel() => _s.cancel();
}

/// Batas token per potongan (pengaman bila model "mengoceh"). Laju tertinggi
/// pada uji At-Tahrim ±5 token/detik; batas 12 token/detik memberi
/// kelonggaran untuk bacaan yang jauh lebih cepat.
int maxTokensFor(double seconds) => math.min(220, (seconds * 12).ceil() + 16);

/// Konteks audio encoder sepanjang potongan (bukan 30 detik penuh): pada uji
/// At-Tahrim hasilnya sama dan proses ±40% lebih cepat.
int audioCtxFor(double seconds) => math.min(1500, (seconds * 50).floor() + 64);

String? _whisperLib;

/// Pustaka native yang dipakai: varian dot-product (±2x lebih cepat) bila
/// prosesor 64-bit mendukung instruksi dot-product dan fp16; selain itu
/// varian umum. Linux hanya menampilkan fitur yang dimiliki semua inti.
Future<String> whisperLibrary() async {
  final cached = _whisperLib;
  if (cached != null) return cached;
  var lib = 'libquran_whisper.so';
  try {
    if (Platform.isAndroid && Abi.current() == Abi.androidArm64) {
      final info = await File('/proc/cpuinfo').readAsString();
      final line = RegExp(r'^Features\s*:\s*(.*)$', multiLine: true)
          .firstMatch(info)
          ?.group(1);
      final features = line?.split(RegExp(r'\s+')).toSet() ?? const <String>{};
      if (features.contains('asimddp') && features.contains('asimdhp')) {
        lib = 'libquran_whisper_dp.so';
      }
    }
  } catch (_) {}
  return _whisperLib = lib;
}
