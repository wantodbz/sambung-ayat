import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../data/quran.dart';

/// Penyimpanan & pengunduhan murottal Syaikh Abdurrahman as-Sudais per ayat.
/// Sumber: EveryAyah.com (64 kbps).
class AudioStore {
  AudioStore._();
  static final AudioStore instance = AudioStore._();

  static const String baseUrl =
      'https://everyayah.com/data/Abdurrahmaan_As-Sudais_64kbps/';

  Directory? _dir;
  Set<String>? _cache;

  Future<Directory> dir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/sudais');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  static String fileName(int s, int a) =>
      '${s.toString().padLeft(3, '0')}${a.toString().padLeft(3, '0')}.mp3';

  Future<String> path(int s, int a) async =>
      '${(await dir()).path}/${fileName(s, a)}';

  /// Daftar nama berkas yang sudah tersimpan.
  Future<Set<String>> available({bool refresh = false}) async {
    if (_cache != null && !refresh) return _cache!;
    final d = await dir();
    final names = <String>{};
    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.mp3')) {
        names.add(e.uri.pathSegments.last);
      }
    }
    _cache = names;
    return names;
  }

  /// Berkas yang diperlukan untuk memutar rangkaian ayat (termasuk basmalah).
  static List<List<int>> requiredFor(List<Ayah> ayahs, {bool basmalah = true}) {
    final req = <List<int>>[];
    var needBasmalah = false;
    for (final a in ayahs) {
      req.add([a.surah, a.ayah]);
      if (a.ayah == 1 && a.surah != 1 && a.surah != 9) needBasmalah = true;
    }
    if (basmalah && needBasmalah) req.add([1, 1]);
    return req;
  }

  Future<List<List<int>>> missing(List<List<int>> refs) async {
    final have = await available();
    return refs.where((r) => !have.contains(fileName(r[0], r[1]))).toList();
  }

  /// Jumlah ayat yang sudah diunduh untuk satu surat.
  Future<int> downloadedCount(int surah) async {
    final have = await available();
    final prefix = surah.toString().padLeft(3, '0');
    return have.where((n) => n.startsWith(prefix)).length;
  }

  Future<void> deleteSurah(int surah) async {
    final d = await dir();
    final prefix = surah.toString().padLeft(3, '0');
    await for (final e in d.list()) {
      final name = e.uri.pathSegments.last;
      if (e is File && name.startsWith(prefix)) {
        // Basmalah (001001) tetap dipertahankan kecuali menghapus Al-Fatihah.
        await e.delete();
      }
    }
    await available(refresh: true);
  }

  /// Unduh daftar berkas. [onProgress] dipanggil (selesai, total).
  /// Melempar [AudioDownloadException] bila ada yang gagal.
  Future<void> download(
    List<List<int>> refs, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final todo = await missing(refs);
    final total = todo.length;
    var done = 0;
    var failed = 0;
    onProgress?.call(0, total);
    if (total == 0) return;
    final d = await dir();
    final client = http.Client();
    var next = 0;

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() ?? false) return;
        if (next >= todo.length) return;
        final r = todo[next++];
        final name = fileName(r[0], r[1]);
        var ok = false;
        for (var attempt = 0; attempt < 3 && !ok; attempt++) {
          try {
            final res = await client
                .get(Uri.parse('$baseUrl$name'))
                .timeout(const Duration(seconds: 60));
            if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
              final tmp = File('${d.path}/$name.part');
              await tmp.writeAsBytes(res.bodyBytes, flush: true);
              await tmp.rename('${d.path}/$name');
              _cache?.add(name);
              ok = true;
            }
          } catch (_) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        }
        if (!ok) failed++;
        done++;
        onProgress?.call(done, total);
      }
    }

    try {
      await Future.wait(List.generate(4, (_) => worker()));
    } finally {
      client.close();
    }
    if (failed > 0) {
      throw AudioDownloadException(failed);
    }
  }
}

class AudioDownloadException implements Exception {
  final int failed;
  AudioDownloadException(this.failed);

  @override
  String toString() =>
      '$failed berkas audio gagal diunduh. Periksa koneksi internet lalu coba lagi.';
}
