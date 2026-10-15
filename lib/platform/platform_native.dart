import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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
