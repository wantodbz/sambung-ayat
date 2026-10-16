import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../data/quran.dart';
import 'reciters.dart';
import 'settings.dart';

/// Penyimpanan & pengunduhan murottal per ayat, terpisah per qari.
/// Sumber: EveryAyah.com (64 kbps). Audio qari yang tidak dipakai tetap
/// disimpan sampai dihapus pengguna.
class AudioStore {
  AudioStore._();
  static final AudioStore instance = AudioStore._();

  final Map<Reciter, Directory> _dirs = {};
  final Map<Reciter, Set<String>> _caches = {};
  bool _oldCleaned = false;

  Reciter _r(Reciter? r) => r ?? Settings.instance.reciter;

  Future<Directory> dir([Reciter? reciter]) async {
    final r = _r(reciter);
    final cached = _dirs[r];
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/${r.dirName}');
    if (!await d.exists()) await d.create(recursive: true);
    if (!_oldCleaned) {
      _oldCleaned = true;
      // Hapus audio murottal lama (as-Sudais, v1.0–1.1) agar memori HP lega.
      final old = Directory('${docs.path}/sudais');
      try {
        if (await old.exists()) await old.delete(recursive: true);
      } catch (_) {}
    }
    _dirs[r] = d;
    return d;
  }

  static String fileName(int s, int a) =>
      '${s.toString().padLeft(3, '0')}${a.toString().padLeft(3, '0')}.mp3';

  Future<String> path(int s, int a, [Reciter? reciter]) async =>
      '${(await dir(reciter)).path}/${fileName(s, a)}';

  /// Daftar nama berkas yang sudah tersimpan.
  Future<Set<String>> available({bool refresh = false, Reciter? reciter}) async {
    final r = _r(reciter);
    final cached = _caches[r];
    if (cached != null && !refresh) return cached;
    final d = await dir(r);
    final names = <String>{};
    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.mp3')) {
        names.add(e.uri.pathSegments.last);
      }
    }
    _caches[r] = names;
    return names;
  }

  /// Ringkasan audio tersimpan satu qari: (jumlah surat lengkap, total byte).
  Future<(int, int)> summary(Reciter reciter) async {
    final d = await dir(reciter);
    final perSurah = <int, int>{};
    var bytes = 0;
    final names = <String>{};
    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.mp3')) {
        final name = e.uri.pathSegments.last;
        names.add(name);
        bytes += await e.length();
        final s = int.tryParse(name.substring(0, 3));
        if (s != null) perSurah[s] = (perSurah[s] ?? 0) + 1;
      }
    }
    _caches[reciter] = names;
    final q = QuranData.instance;
    var full = 0;
    perSurah.forEach((s, n) {
      if (s >= 1 && s <= 114 && n >= q.surah(s).count) full++;
    });
    return (full, bytes);
  }

  /// Hapus seluruh audio satu qari.
  Future<void> deleteAll(Reciter reciter) async {
    final d = await dir(reciter);
    await for (final e in d.list()) {
      if (e is File) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
    _caches[reciter] = <String>{};
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

  Future<List<List<int>>> missing(List<List<int>> refs,
      [Reciter? reciter]) async {
    final have = await available(reciter: reciter);
    return refs.where((r) => !have.contains(fileName(r[0], r[1]))).toList();
  }

  /// Jumlah ayat yang sudah diunduh untuk satu surat.
  Future<int> downloadedCount(int surah, [Reciter? reciter]) async {
    final have = await available(reciter: reciter);
    final prefix = surah.toString().padLeft(3, '0');
    return have.where((n) => n.startsWith(prefix)).length;
  }

  Future<void> deleteSurah(int surah, [Reciter? reciter]) async {
    final d = await dir(reciter);
    final prefix = surah.toString().padLeft(3, '0');
    await for (final e in d.list()) {
      final name = e.uri.pathSegments.last;
      if (e is File && name.startsWith(prefix)) {
        await e.delete();
      }
    }
    await available(refresh: true, reciter: reciter);
  }

  /// Unduh daftar berkas. [onProgress] dipanggil (selesai, total).
  /// Melempar [AudioDownloadException] bila ada yang gagal.
  Future<void> download(
    List<List<int>> refs, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
    Reciter? reciter,
  }) async {
    final r = _r(reciter);
    final todo = await missing(refs, r);
    final total = todo.length;
    var done = 0;
    var failed = 0;
    onProgress?.call(0, total);
    if (total == 0) return;
    final d = await dir(r);
    final cache = _caches[r];
    final client = http.Client();
    var next = 0;

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() ?? false) return;
        if (next >= todo.length) return;
        final ref = todo[next++];
        final name = fileName(ref[0], ref[1]);
        var ok = false;
        for (final url in r.urlsFor(name)) {
          var notFound = false;
          for (var attempt = 0; attempt < 3 && !ok && !notFound; attempt++) {
            try {
              final res = await client
                  .get(Uri.parse(url))
                  .timeout(const Duration(seconds: 60));
              if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
                final tmp = File('${d.path}/$name.part');
                await tmp.writeAsBytes(res.bodyBytes, flush: true);
                await tmp.rename('${d.path}/$name');
                cache?.add(name);
                ok = true;
              } else if (res.statusCode == 404) {
                notFound = true; // coba folder cadangan
              }
            } catch (_) {
              await Future<void>.delayed(const Duration(seconds: 1));
            }
          }
          if (ok) break;
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
