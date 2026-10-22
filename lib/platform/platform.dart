/// Lapisan platform: Android/iPhone (native) vs versi web (PWA).
library;

import 'dart:async';
import 'dart:typed_data';

import '../services/model_store.dart';

import 'platform_stub.dart'
    if (dart.library.js_interop) 'platform_web.dart'
    if (dart.library.ffi) 'platform_native.dart' as impl;

/// Kejadian selama transkripsi Murajaah.
class TxEvent {
  final int done;
  final int total;
  final String text;
  final String? error;
  final bool finished;
  const TxEvent(this.done, this.total, this.text,
      {this.error, this.finished = false});
}

/// Pengenal suara untuk Sambung Ayat.
abstract class SpeechEngine {
  void Function(String text, bool isFinal, int session)? onResult;
  void Function(String message)? onFatalError;
  void Function(bool listening)? onListeningChanged;
  void Function(bool processing)? onProcessingChanged;

  /// Dipanggil saat suara bacaan mulai terdengar (menghentikan hitung mundur).
  void Function()? onActivity;

  /// Dipanggil berkala selama terdengar suara (tingkat suara mikrofon);
  /// dipakai untuk mengetahui kapan pengguna berhenti membaca.
  void Function()? onSound;

  Future<bool> init();
  Future<void> start();
  Future<void> stop();
  bool get isListening;

  /// Web: segera akhiri potongan rekaman sekarang dan periksa.
  bool get supportsFlush => false;
  void flush() {}

  /// Web: dipanggil langsung dari ketukan pengguna (aturan iPhone).
  Future<void> prepareFromGesture() async {}
}

/// Pemutar murottal untuk Sambung Ayat.
abstract class MurottalPlayer {
  /// Putar satu ayat sampai selesai.
  Future<void> play(int surah, int ayah);
  Future<void> stop();
  Future<void> dispose();

  /// Web: buka izin audio dari ketukan pengguna.
  void unlockFromGesture() {}
}

/// Transkripsi bertahap Murajaah: potongan rekaman dikirim satu per satu
/// selama anak membaca dan diproses berurutan di latar belakang.
abstract class LiveTranscriber {
  /// Teks tiap potongan yang selesai (berurutan). Setelah [close], kejadian
  /// terakhir bertanda `finished`.
  Stream<TxEvent> get events;

  /// Jumlah potongan yang sudah dikirim.
  int get submitted;

  /// Kirim satu potongan PCM 16-bit 16 kHz mono.
  void add(Int16List chunk);

  /// Tidak ada potongan lagi; selesaikan antrean.
  void close();

  /// Hentikan segera dan buang antrean.
  Future<void> cancel();
}

/// Kebutuhan Murajaah: model, perekaman, transkripsi.
abstract class MurajaahIO {
  /// Native: rekaman dialirkan sebagai PCM agar bisa diperiksa sambil
  /// membaca (tanpa berkas rekaman). Web: false (diperiksa setelah selesai).
  bool get supportsLive => false;

  /// Mulai merekam sebagai aliran PCM 16-bit 16 kHz mono.
  Future<void> startLiveRecording(void Function(Int16List samples) onSamples) =>
      throw UnsupportedError('live');

  /// Hentikan aliran rekaman (sisa suara dikirim dulu ke onSamples).
  Future<void> stopLiveRecording() async {}

  /// Siapkan pemeriksa bertahap dengan model [m].
  Future<LiveTranscriber> openLiveTranscriber(QuranModel m) =>
      throw UnsupportedError('live');

  Future<bool> hasModel(QuranModel m);
  Future<int> modelSize(QuranModel m);
  Future<void> downloadModel(QuranModel m,
      {void Function(int received, int total)? onProgress,
      bool Function()? isCancelled});
  Future<void> deleteModel(QuranModel m);

  /// Web: perekaman harus dimulai dari ketukan pengguna.
  bool get needsGesture;

  /// Buka mikrofon (minta izin). false bila ditolak.
  Future<bool> openRecorder();
  Future<void> startRecording();
  double get level;
  Future<Float32List?> stopRecording();
  Future<void> discardRecording();
  Future<void> closeRecorder();

  Stream<TxEvent> transcribe(QuranModel m, List<Float32List> chunks);

  /// Bersihkan sisa rekaman/unduhan.
  Future<void> cleanup();
}

final SpeechEngine speechEngine = impl.createSpeechEngine();
MurottalPlayer createMurottalPlayer() => impl.createMurottalPlayer();
final MurajaahIO murajaahIO = impl.createMurajaahIO();

/// Versi web: audio diputar langsung dari internet (tanpa unduh per surat).
const bool streamsAudio = impl.streamsAudio;

/// Versi web: browser punya pengenal suara bawaan (Sambung Ayat tanpa model).
bool get browserSpeech => impl.browserSpeech();

/// Jaga layar tetap menyala selama sesi latihan. Bila layar mati, HP
/// memperlambat atau menghentikan proses (pemeriksaan Murajaah jadi sangat
/// lama, mikrofon Sambung Ayat berhenti).
Future<void> keepScreenOn(bool on) => impl.keepScreenOn(on);
