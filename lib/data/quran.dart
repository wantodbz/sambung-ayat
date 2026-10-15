import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Satu ayat Al-Qur'an.
class Ayah {
  final int surah;
  final int ayah;
  final String text;

  const Ayah(this.surah, this.ayah, this.text);
}

/// Satu surat Al-Qur'an.
class Surah {
  final int number;
  final String name; // nama Arab
  final String latin; // nama latin
  final bool makkiyah;
  final List<String> verses;

  const Surah(this.number, this.name, this.latin, this.makkiyah, this.verses);

  int get count => verses.length;
}

/// Data teks Al-Qur'an (Rasm Utsmani) yang dimuat dari aset.
class QuranData {
  QuranData._(this.surahs, this.juzStarts);

  final List<Surah> surahs;

  /// Awal setiap juz: [surat, ayat].
  final List<List<int>> juzStarts;

  static QuranData? _instance;

  static Future<QuranData> load() async {
    if (_instance != null) return _instance!;
    final raw = await rootBundle.loadString('assets/quran.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final list = map['surahs'] as List<dynamic>;
    final surahs = <Surah>[];
    for (var i = 0; i < list.length; i++) {
      final s = list[i] as Map<String, dynamic>;
      surahs.add(Surah(
        i + 1,
        s['name'] as String,
        s['latin'] as String,
        s['type'] == 'meccan',
        (s['verses'] as List<dynamic>).cast<String>(),
      ));
    }
    final juz = (map['juz'] as List<dynamic>)
        .map((e) => (e as List<dynamic>).cast<int>())
        .toList();
    _instance = QuranData._(surahs, juz);
    return _instance!;
  }

  static QuranData get instance => _instance!;

  Surah surah(int number) => surahs[number - 1];

  Ayah ayah(int s, int a) => Ayah(s, a, surahs[s - 1].verses[a - 1]);

  /// Semua ayat dalam satu surat.
  List<Ayah> rangeSurah(int s) =>
      [for (var a = 1; a <= surah(s).count; a++) ayah(s, a)];

  /// Semua ayat dalam satu juz (1–30).
  List<Ayah> rangeJuz(int juz) {
    final start = juzStarts[juz - 1];
    final List<int> end; // eksklusif
    if (juz < 30) {
      end = juzStarts[juz];
    } else {
      end = [115, 1];
    }
    final result = <Ayah>[];
    var s = start[0];
    var a = start[1];
    while (s < end[0] || (s == end[0] && a < end[1])) {
      if (s > 114) break;
      result.add(ayah(s, a));
      a++;
      if (a > surah(s).count) {
        s++;
        a = 1;
      }
    }
    return result;
  }

  /// Keterangan singkat cakupan juz, mis. "Al-Baqarah 142 – Al-Baqarah 252".
  String juzLabel(int juz) {
    final r = rangeJuz(juz);
    final f = r.first;
    final l = r.last;
    return '${surah(f.surah).latin} ${f.ayah} – ${surah(l.surah).latin} ${l.ayah}';
  }
}
