/// Pengenal bacaan Al-Qur'an offline (whisper.cpp) — dipakai menu Murajaah.
library quran_whisper;

import 'dart:async';
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
      final lib = Platform.isAndroid
          ? DynamicLibrary.open('libquran_whisper.so')
          : DynamicLibrary.process();
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
        final text = len > 0 ? out.cast<Utf8>().toDartString(length: len) : '';
        send.send(['progress', i + 1, total, text]);
      }
      malloc.free(out);
      free(ctx);
      send.send(['done', total]);
    } catch (e) {
      send.send(['error', '$e']);
    }
  }
}
