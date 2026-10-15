import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/quran.dart';

/// Satu baris laporan: surat yang sudah dibaca dengan benar.
class ReportEntry {
  final int surah;
  final DateTime date;
  final String mode; // 'Sambung Ayat' / 'Murajaah'
  final int errors;
  final int times; // berapa kali surat ini lulus

  const ReportEntry(this.surah, this.date, this.mode, this.errors, this.times);

  Map<String, dynamic> toJson() => {
        's': surah,
        'd': date.toIso8601String(),
        'm': mode,
        'e': errors,
        't': times,
      };

  static ReportEntry fromJson(Map<String, dynamic> j) => ReportEntry(
        j['s'] as int,
        DateTime.parse(j['d'] as String),
        j['m'] as String,
        j['e'] as int,
        (j['t'] as int?) ?? 1,
      );
}

/// Laporan untuk orang tua + kata sandi orang tua.
class ParentReport {
  ParentReport._();
  static final ParentReport instance = ParentReport._();

  static const _kReport = 'report_v1';
  static const _kPassword = 'parent_pw_v1';

  final Map<int, ReportEntry> _entries = {};
  String? _password; // "salt:hash"

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _password = p.getString(_kPassword);
    _entries.clear();
    final raw = p.getString(_kReport);
    if (raw != null) {
      try {
        for (final e in (jsonDecode(raw) as List<dynamic>)) {
          final r = ReportEntry.fromJson(e as Map<String, dynamic>);
          _entries[r.surah] = r;
        }
      } catch (_) {}
    }
  }

  List<ReportEntry> get entries =>
      _entries.values.toList()..sort((a, b) => a.surah.compareTo(b.surah));

  bool get hasPassword => _password != null;

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kReport, jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  /// Catat surat yang dibaca dengan benar sampai selesai.
  Future<void> record(int surah, String mode, int errors) async {
    final prev = _entries[surah];
    _entries[surah] = ReportEntry(
        surah, DateTime.now(), mode, errors, (prev?.times ?? 0) + 1);
    await _save();
  }

  /// Hitung surat yang tercakup penuh oleh [ayahs], lalu catat yang lulus.
  /// [failed] = ayat yang tidak lulus; [errorsOf] = jumlah kesalahan per ayat.
  /// Mengembalikan daftar surat yang tercatat.
  Future<List<int>> recordSession({
    required List<Ayah> ayahs,
    required String mode,
    required bool Function(Ayah a) failed,
    required int Function(Ayah a) errorsOf,
  }) async {
    final bySurah = <int, List<Ayah>>{};
    for (final a in ayahs) {
      bySurah.putIfAbsent(a.surah, () => []).add(a);
    }
    final q = QuranData.instance;
    final recorded = <int>[];
    for (final e in bySurah.entries) {
      if (e.value.length != q.surah(e.key).count) continue; // tidak utuh
      if (e.value.any(failed)) continue; // kriteria: semua ayat benar
      final errors = e.value.fold<int>(0, (sum, a) => sum + errorsOf(a));
      await record(e.key, mode, errors);
      recorded.add(e.key);
    }
    return recorded;
  }

  static String _hash(String salt, String password) =>
      sha256.convert(utf8.encode('$salt|$password')).toString();

  Future<void> setPassword(String password) async {
    final rnd = Random.secure();
    final salt = base64Url.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    _password = '$salt:${_hash(salt, password)}';
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPassword, _password!);
  }

  bool verify(String password) {
    final stored = _password;
    if (stored == null) return false;
    final i = stored.indexOf(':');
    return _hash(stored.substring(0, i), password) == stored.substring(i + 1);
  }

  Future<bool> reset(String password) async {
    if (!verify(password)) return false;
    _entries.clear();
    await _save();
    return true;
  }
}
