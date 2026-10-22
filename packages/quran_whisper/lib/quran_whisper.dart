/// Pengenal bacaan Al-Qur'an offline (whisper.cpp) — dipakai menu Murajaah.
library quran_whisper;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _InitC = Pointer<Void> Function(Pointer<Utf8>);
typedef _InitD = Pointer<Void> Function(Pointer<Utf8>);
typedef _TrC = Int32 Function(
    Pointer<Void>, Pointer<Float>, Int32, Int32, Pointer<Uint8>, Int32);
typedef _TrD = int Function(
    Pointer<Void>, Pointer<Float>, int, int, Pointer<Uint8>, int);
typedef _TrExC = Int32 Function(Pointer<Void>, Pointer<Float>, Int32, Int32,
    Int32, Int32, Int32, Pointer<Uint8>, Int32);
typedef _TrExD = int Function(
    Pointer<Void>, Pointer<Float>, int, int, int, int, int, Pointer<Uint8>, int);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);

/// Kejadian selama transkripsi.
class TranscribeEvent {
  /// Potongan yang sudah selesai diproses.
  final int done;
  final int total;

  /// Teks potongan terakhir yang selesai (boleh kosong).
  final String text;

  /// Berisi pesan bila gagal.
  final String? error;

  /// true bila seluruh potongan sudah selesai.
  final bool finished;

  const TranscribeEvent(this.done, this.total, this.text,
      {this.error, this.finished = false});
}

DynamicLibrary _open(String library) => Platform.isAndroid
    ? DynamicLibrary.open(library)
    : (Platform.isIOS || Platform.isMacOS)
        ? DynamicLibrary.open('quran_whisper.framework/quran_whisper')
        : DynamicLibrary.process();

String _decode(Pointer<Uint8> out, int len) =>
    len > 0 ? utf8.decode(out.asTypedList(len), allowMalformed: true) : '';

class QuranWhisper {
  QuranWhisper._();

  /// Transkripsi [chunks] (PCM float 16 kHz mono) satu per satu di isolate
  /// terpisah, model dimuat sekali. Batalkan dengan membatalkan langganan.
  static Stream<TranscribeEvent> transcribe({
    required String modelPath,
    required List<Float32List> chunks,
    int threads = 4,
  }) {
    late StreamController<TranscribeEvent> controller;
    Isolate? isolate;
    final port = ReceivePort();

    Future<void> start() async {
      final data = [
        for (final c in chunks)
          TransferableTypedData.fromList([c.buffer.asUint8List(c.offsetInBytes, c.lengthInBytes)])
      ];
      isolate = await Isolate.spawn(
        _worker,
        [port.sendPort, modelPath, data, threads],
        errorsAreFatal: true,
      );
    }

    controller = StreamController<TranscribeEvent>(
      onListen: () {
        port.listen((msg) {
          final m = msg as List<dynamic>;
          switch (m[0] as String) {
            case 'progress':
              controller.add(TranscribeEvent(m[1] as int, m[2] as int, m[3] as String));
            case 'done':
              controller.add(TranscribeEvent(m[1] as int, m[1] as int, '',
                  finished: true));
              port.close();
              controller.close();
            case 'error':
              controller.add(TranscribeEvent(0, chunks.length, '',
                  error: m[1] as String));
              port.close();
              controller.close();
          }
        });
        start().catchError((Object e) {
          controller.add(TranscribeEvent(0, chunks.length, '', error: '$e'));
          port.close();
          controller.close();
        });
      },
      onCancel: () {
        isolate?.kill(priority: Isolate.immediate);
        port.close();
      },
    );
    return controller.stream;
  }

  static void _worker(List<dynamic> args) {
    final send = args[0] as SendPort;
    final modelPath = args[1] as String;
    final data = (args[2] as List<dynamic>).cast<TransferableTypedData>();
    final threads = args[3] as int;

    try {
      final lib = _open('libquran_whisper.so');
      final init = lib.lookupFunction<_InitC, _InitD>('qw_init');
      final tr = lib.lookupFunction<_TrC, _TrD>('qw_transcribe');
      final free = lib.lookupFunction<_FreeC, _FreeD>('qw_free');

      final pathPtr = modelPath.toNativeUtf8();
      final ctx = init(pathPtr);
      malloc.free(pathPtr);
      if (ctx == nullptr) {
        send.send(['error', 'Model pengenal bacaan gagal dimuat.']);
        return;
      }

      const outLen = 32768;
      final out = malloc<Uint8>(outLen);
      final total = data.length;
      for (var i = 0; i < total; i++) {
        final bytes = data[i].materialize().asUint8List();
        final n = bytes.lengthInBytes ~/ 4;
        final pcm = malloc<Float>(n);
        pcm.asTypedList(n).setAll(0, bytes.buffer.asFloat32List(bytes.offsetInBytes, n));
        final len = tr(ctx, pcm, n, threads, out, outLen);
        malloc.free(pcm);
        send.send(['progress', i + 1, total, _decode(out, len)]);
      }
      malloc.free(out);
      free(ctx);
      send.send(['done', total]);
    } catch (e) {
      send.send(['error', '$e']);
    }
  }
}

/// Transkripsi bertahap: potongan PCM 16-bit dikirim satu per satu (misalnya
/// sambil merekam) dan diproses berurutan di isolate terpisah; model dimuat
/// sekali. [events] memberi teks tiap potongan; setelah [close] dan antrean
/// habis, kejadian terakhir bertanda `finished`.
class WhisperSession {
  WhisperSession._();

  final _events = StreamController<TranscribeEvent>();
  final _port = ReceivePort();
  final _exitPort = ReceivePort();
  Isolate? _isolate;
  SendPort? _worker;
  final _pending = <Object>[];
  int _submitted = 0;
  int _done = 0;
  bool _closed = false;
  bool _ended = false;

  Stream<TranscribeEvent> get events => _events.stream;
  int get submitted => _submitted;
  int get done => _done;

  /// Mulai sesi. [library]: nama pustaka native (varian prosesor).
  static WhisperSession start({
    required String modelPath,
    int threads = 4,
    String library = 'libquran_whisper.so',
  }) {
    final s = WhisperSession._();
    s._port.listen(s._onMessage);
    s._exitPort.listen((_) {
      // Beri kesempatan pesan terakhir ("done") diproses lebih dulu.
      Timer(const Duration(milliseconds: 300), () {
        if (!s._ended) s._fail('Pemeriksa bacaan berhenti tiba-tiba.');
      });
    });
    Isolate.spawn(
      _sessionWorker,
      [s._port.sendPort, modelPath, threads, library],
      onExit: s._exitPort.sendPort,
      errorsAreFatal: true,
    ).then((iso) {
      s._isolate = iso;
      if (s._ended) iso.kill(priority: Isolate.immediate);
    }).catchError((Object e) {
      s._fail('$e');
    });
    return s;
  }

  /// Kirim satu potongan. [maxTokens]: batas token (0 = tanpa batas);
  /// [audioCtx]: konteks audio encoder (0 = penuh).
  void add(Int16List pcm, {int maxTokens = 0, int audioCtx = 0}) {
    if (_closed || _ended) return;
    _submitted++;
    _send([
      'chunk',
      TransferableTypedData.fromList(
          [pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes)]),
      maxTokens,
      audioCtx,
    ]);
  }

  /// Tidak ada potongan lagi.
  void close() {
    if (_closed || _ended) return;
    _closed = true;
    _send(const ['end']);
  }

  /// Hentikan segera; antrean dibuang.
  Future<void> cancel() async {
    if (_ended) return;
    _ended = true;
    _isolate?.kill(priority: Isolate.immediate);
    _cleanup();
  }

  void _send(Object msg) {
    final w = _worker;
    if (w == null) {
      _pending.add(msg);
    } else {
      w.send(msg);
    }
  }

  void _onMessage(dynamic msg) {
    if (_ended) return;
    final m = msg as List<dynamic>;
    switch (m[0] as String) {
      case 'port':
        final w = _worker = m[1] as SendPort;
        for (final p in _pending) {
          w.send(p);
        }
        _pending.clear();
      case 'text':
        _done = m[1] as int;
        _events.add(TranscribeEvent(_done, _submitted, m[2] as String));
      case 'done':
        _events.add(TranscribeEvent(_done, _submitted, '', finished: true));
        _ended = true;
        _cleanup();
      case 'error':
        _fail(m[1] as String);
    }
  }

  void _fail(String error) {
    if (_ended) return;
    _ended = true;
    _events.add(TranscribeEvent(_done, _submitted, '', error: error));
    _isolate?.kill(priority: Isolate.immediate);
    _cleanup();
  }

  void _cleanup() {
    _port.close();
    _exitPort.close();
    if (!_events.isClosed) _events.close();
  }

  static void _sessionWorker(List<dynamic> args) {
    final send = args[0] as SendPort;
    final modelPath = args[1] as String;
    final threads = args[2] as int;
    final library = args[3] as String;
    final inbox = ReceivePort();
    send.send(['port', inbox.sendPort]);

    final _TrExD tr;
    final _FreeD free;
    final Pointer<Void> ctx;
    try {
      DynamicLibrary lib;
      try {
        lib = _open(library);
      } catch (_) {
        lib = _open('libquran_whisper.so'); // varian umum sebagai cadangan
      }
      final init = lib.lookupFunction<_InitC, _InitD>('qw_init');
      tr = lib.lookupFunction<_TrExC, _TrExD>('qw_transcribe_ex');
      free = lib.lookupFunction<_FreeC, _FreeD>('qw_free');
      final pathPtr = modelPath.toNativeUtf8();
      ctx = init(pathPtr);
      malloc.free(pathPtr);
    } catch (e) {
      send.send(['error', '$e']);
      inbox.close();
      return;
    }
    if (ctx == nullptr) {
      send.send(['error', 'Model pengenal bacaan gagal dimuat.']);
      inbox.close();
      return;
    }

    const outLen = 32768;
    final out = malloc<Uint8>(outLen);
    var index = 0;
    inbox.listen((msg) {
      final m = msg as List<dynamic>;
      if (m[0] == 'chunk') {
        final bytes = (m[1] as TransferableTypedData).materialize().asUint8List();
        final n = bytes.lengthInBytes ~/ 2;
        final s16 = bytes.buffer.asInt16List(bytes.offsetInBytes, n);
        final pcm = malloc<Float>(n);
        final f = pcm.asTypedList(n);
        for (var i = 0; i < n; i++) {
          f[i] = s16[i] / 32768.0;
        }
        final len = tr(ctx, pcm, n, threads, m[2] as int, m[3] as int, 0, out, outLen);
        malloc.free(pcm);
        index++;
        send.send(['text', index, _decode(out, len)]);
      } else {
        malloc.free(out);
        free(ctx);
        send.send(['done', index]);
        inbox.close();
      }
    });
  }
}
