import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Model pengenal bacaan Al-Qur'an (Whisper, tarteel-ai) untuk Murajaah.
enum QuranModel { cepat, akurat }

extension QuranModelX on QuranModel {
  String get fileName => switch (this) {
        QuranModel.cepat => 'ggml-quran-tiny.bin',
        QuranModel.akurat => 'ggml-quran-base.bin',
      };

  String get label => switch (this) {
        QuranModel.cepat => 'Cepat',
        QuranModel.akurat => 'Akurat',
      };

  /// Ukuran asli berkas model (bita), untuk memeriksa keutuhan unduhan.
  int get bytes => switch (this) {
        QuranModel.cepat => 43537433,
        QuranModel.akurat => 81768585,
      };

  String get hint => switch (this) {
        QuranModel.cepat =>
          'Unduhan ±45 MB. Koreksi lebih cepat, cocok untuk HP lama.',
        QuranModel.akurat =>
          'Unduhan ±80 MB. Lebih teliti, koreksi sedikit lebih lama.',
      };
}

class ModelStore {
  ModelStore._();
  static final ModelStore instance = ModelStore._();

  static const String baseUrl =
      'https://github.com/wantodbz/sambung-ayat/releases/download/model-v1/';

  Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/models');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<String> path(QuranModel m) async => '${(await _dir()).path}/${m.fileName}';

  Future<bool> has(QuranModel m) async {
    final f = File(await path(m));
    return await f.exists() && await f.length() > 10 * 1024 * 1024;
  }

  /// Ukuran berkas model yang tersimpan (byte), 0 bila belum ada.
  Future<int> size(QuranModel m) async {
    final f = File(await path(m));
    return await f.exists() ? await f.length() : 0;
  }

  /// Hapus sisa unduhan yang tidak selesai.
  Future<void> cleanupPartial() async {
    try {
      await for (final e in (await _dir()).list()) {
        if (e is File && e.path.endsWith('.part')) await e.delete();
      }
    } catch (_) {}
  }

  Future<void> delete(QuranModel m) async {
    final f = File(await path(m));
    if (await f.exists()) await f.delete();
  }

  /// Unduh model. [onProgress] menerima (byte diterima, total byte atau -1).
  Future<void> download(
    QuranModel m, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final target = await path(m);
    final part = File('$target.part');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse('$baseUrl${m.fileName}')));
      if (res.statusCode != 200) {
        throw Exception('Server menjawab ${res.statusCode}');
      }
      final total = res.contentLength ?? -1;
      final sink = part.openWrite();
      var received = 0;
      try {
        await for (final chunk in res.stream) {
          if (isCancelled?.call() ?? false) {
            throw const _Cancelled();
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && received != total) {
        throw Exception('Unduhan terputus. Silakan coba lagi.');
      }
      await part.rename(target);
    } catch (e) {
      if (await part.exists()) await part.delete();
      if (e is _Cancelled) return;
      rethrow;
    } finally {
      client.close();
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
