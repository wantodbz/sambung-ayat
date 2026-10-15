import 'dart:math' as math;

import '../data/quran.dart';

enum Verdict { correct, wrong, notRead }

/// Hasil koreksi satu ayat pada murajaah.
class AyahVerdict {
  final Ayah ayah;
  final Verdict verdict;
  final double similarity;
  const AyahVerdict(this.ayah, this.verdict, this.similarity);
}

/// Hasil pencocokan bacaan dengan satu ayat.
class MatchResult {
  /// Kemiripan 0..1.
  final double similarity;

  /// Jumlah karakter (ternormalisasi) dari teks terdengar yang dipakai ayat ini.
  final int consumed;

  /// Apakah akhir ayat sudah terbaca.
  final bool tailOk;

  const MatchResult(this.similarity, this.consumed, this.tailOk);

  static const empty = MatchResult(0, 0, false);
}

/// Pencocok teks Arab yang toleran terhadap perbedaan rasm Utsmani
/// dan keluaran pengenal suara (tanpa harakat, ejaan imla'i).
///
/// Pencocokan dilakukan pada tingkat huruf (bukan kata) sehingga tetap
/// andal walaupun pemenggalan kata berbeda, mis. "يَٰٓأَيُّهَا" vs "يا أيها".
class ArabicMatcher {
  ArabicMatcher._();

  /// Normalisasi: hapus harakat & tanda waqaf, satukan bentuk huruf,
  /// hapus alif (karena rasm Utsmani sering membuang/menyisipkan alif),
  /// dan hapus spasi.
  static String normalize(String input) {
    final sb = StringBuffer();
    for (final r in input.runes) {
      // Harakat, tanwin, sukun, syaddah, tanda Qur'ani, tatwil, alif kecil.
      if ((r >= 0x0610 && r <= 0x061A) ||
          (r >= 0x064B && r <= 0x065F) ||
          r == 0x0670 ||
          (r >= 0x06D6 && r <= 0x06ED) ||
          r == 0x0640) {
        continue;
      }
      switch (r) {
        case 0x0621: // ء
        case 0x0622: // آ
        case 0x0623: // أ
        case 0x0625: // إ
        case 0x0627: // ا
        case 0x0671: // ٱ
          continue;
        case 0x0624: // ؤ
          sb.writeCharCode(0x0648);
          continue;
        case 0x0626: // ئ
        case 0x0649: // ى
        case 0x06CC: // ی
          sb.writeCharCode(0x064A);
          continue;
        case 0x0629: // ة
          sb.writeCharCode(0x0647);
          continue;
        case 0x06A9: // ک
          sb.writeCharCode(0x0643);
          continue;
      }
      if (r >= 0x0621 && r <= 0x064A) sb.writeCharCode(r);
    }
    return sb.toString();
  }

  /// Jarak edit antara seluruh [a] dan setiap awalan [b].
  /// Hasil[j] = jarak(a, b.substring(0, j)).
  static List<int> lastRow(String a, String b) {
    final n = b.length;
    var prev = List<int>.generate(n + 1, (j) => j);
    var cur = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      final ca = a.codeUnitAt(i - 1);
      for (var j = 1; j <= n; j++) {
        final cost = ca == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = prev[j - 1] + cost;
        final del = prev[j] + 1;
        final ins = cur[j - 1] + 1;
        if (del < v) v = del;
        if (ins < v) v = ins;
        cur[j] = v;
      }
      final t = prev;
      prev = cur;
      cur = t;
    }
    return prev;
  }

  static int distance(String a, String b) => lastRow(a, b)[b.length];

  static double similarity(String a, String b) {
    final m = math.max(a.length, b.length);
    if (m == 0) return 1;
    return 1 - distance(a, b) / m;
  }

  /// Cocokkan [heard] (ternormalisasi) dengan awal teks terdengar.
  /// Mencari potongan awal [heard] yang paling mirip dengan [expected].
  static MatchResult matchStart(String expected, String heard) {
    if (heard.isEmpty || expected.isEmpty) return MatchResult.empty;
    final row = lastRow(expected, heard);
    final l = expected.length;
    var bestSim = -1.0;
    var bestJ = 0;
    final minJ = math.max(1, (l * 0.5).floor());
    for (var j = minJ; j <= heard.length; j++) {
      final s = 1 - row[j] / math.max(l, j);
      if (s > bestSim + 1e-9) {
        bestSim = s;
        bestJ = j;
      }
    }
    if (bestSim < 0) return MatchResult(0, 0, false);

    // Periksa bahwa akhir ayat benar-benar sudah terucap.
    final tailLen = math.min(8, l);
    final tail = expected.substring(l - tailLen);
    var tailSim = 0.0;
    for (var w = tailLen - 2; w <= tailLen + 2; w++) {
      if (w <= 0) continue;
      final st = bestJ - w;
      if (st < 0) continue;
      final s = similarity(tail, heard.substring(st, bestJ));
      if (s > tailSim) tailSim = s;
    }
    return MatchResult(bestSim, bestJ, tailSim >= 0.6);
  }

  /// Seberapa mirip [heard] dengan bagian AWAL [expected] (untuk deteksi dini
  /// bila pengguna membaca ayat yang salah).
  static double prefixSimilarity(String expected, String heard) {
    if (heard.isEmpty) return 1;
    final row = lastRow(heard, expected);
    final m = heard.length;
    var best = 0.0;
    for (var j = 1; j <= expected.length; j++) {
      final s = 1 - row[j] / math.max(m, j);
      if (s > best) best = s;
    }
    return best;
  }

  // ---------------------------------------------------------------------------
  // Basmalah, ta'awudz, dan huruf muqatta'ah.

  static final String basmalah =
      normalize('بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ');
  static final String taawudz = normalize('أعوذ بالله من الشيطان الرجيم');

  /// Buang ta'awudz/basmalah di awal bacaan bila ayat yang diharapkan
  /// tidak diawali basmalah. Mengembalikan jumlah karakter yang dibuang.
  static int leadingExtras(String heard, String expected) {
    var cut = 0;
    for (final p in [taawudz, basmalah]) {
      if (expected.startsWith(basmalah) && identical(p, basmalah)) continue;
      final rest = heard.substring(cut);
      if (rest.length < (p.length * 0.85).floor()) continue;
      final r = matchStart(p, rest);
      if (r.similarity >= 0.8) cut += r.consumed;
    }
    return cut;
  }

  /// Apakah [heard] kemungkinan sedang membaca ta'awudz/basmalah.
  static bool looksLikeOpening(String heard) =>
      prefixSimilarity(basmalah, heard) >= 0.7 ||
      prefixSimilarity(taawudz, heard) >= 0.7;

  static const Map<int, String> _letterNames = {
    0x0627: 'الف',
    0x0644: 'لام',
    0x0645: 'ميم',
    0x0635: 'صاد',
    0x0631: 'را',
    0x0643: 'كاف',
    0x0647: 'ها',
    0x064A: 'يا',
    0x0639: 'عين',
    0x0637: 'طا',
    0x0633: 'سين',
    0x062D: 'حا',
    0x0642: 'قاف',
    0x0646: 'نون',
  };

  static const Set<int> _muqattaahSurahs = {
    2, 3, 7, 10, 11, 12, 13, 14, 15, 19, 20, 26, 27, 28, 29, 30, 31, 32, //
    36, 38, 40, 41, 42, 43, 44, 45, 46, 50, 68,
  };

  static bool _hasMuqattaah(Ayah a) =>
      (a.ayah == 1 && _muqattaahSurahs.contains(a.surah)) ||
      (a.surah == 42 && a.ayah == 2);

  // ---------------------------------------------------------------------------
  // Koreksi murajaah di akhir: menyelaraskan seluruh bacaan dengan rangkaian ayat.

  /// Selaraskan [expected] dengan [heard] mulai dari [from]; awal boleh bergeser
  /// sampai [slack] huruf. Biaya: substitusi 2, huruf berlebih 2, huruf ayat
  /// yang tidak tertangkap 1 (karena celah jeda pengenal suara).
  /// Mengembalikan (kemiripan, posisi akhir).
  static (double, int) alignSegment(
      String expected, String heard, int from, int slack) {
    final l = expected.length;
    final end = math.min(heard.length, from + slack + 2 * l + 40);
    if (from >= end || l == 0) return (0.0, from);
    final s = heard.substring(from, end);
    final n = s.length;
    var prev = List<int>.generate(n + 1, (j) => j <= slack ? 0 : 2 * (j - slack));
    var cur = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= l; i++) {
      cur[0] = i;
      final ca = expected.codeUnitAt(i - 1);
      for (var j = 1; j <= n; j++) {
        var v = prev[j - 1] + (ca == s.codeUnitAt(j - 1) ? 0 : 2);
        final miss = prev[j] + 1;
        final extra = cur[j - 1] + 2;
        if (miss < v) v = miss;
        if (extra < v) v = extra;
        cur[j] = v;
      }
      final t = prev;
      prev = cur;
      cur = t;
    }
    var bj = 0;
    for (var j = 1; j <= n; j++) {
      if (prev[j] < prev[bj]) bj = j;
    }
    return (1 - prev[bj] / (2 * l), from + bj);
  }

  static (double, int) _bestAlign(Ayah a, String heard, int pos, int slack) {
    var best = (-1.0, pos);
    for (final c in candidates(a)) {
      final r = alignSegment(c, heard, pos, slack);
      if (r.$1 > best.$1) best = r;
    }
    return best;
  }

  /// Periksa seluruh bacaan [heard] (ternormalisasi) terhadap [ayahs].
  static List<AyahVerdict> review(
      List<Ayah> ayahs, String heard, double threshold) {
    final result = <AyahVerdict>[];
    if (ayahs.isEmpty) return result;
    var pos = leadingExtras(heard, candidates(ayahs.first).first);
    var slack = 25;
    for (var i = 0; i < ayahs.length; i++) {
      final a = ayahs[i];
      if (pos >= heard.length - 1) {
        result.add(AyahVerdict(a, Verdict.notRead, 0));
        continue;
      }
      if (a.ayah == 1) slack = math.max(slack, 25); // basmalah di awal surat
      final best = _bestAlign(a, heard, pos, slack);
      if (best.$1 >= threshold) {
        result.add(AyahVerdict(a, Verdict.correct, best.$1));
        pos = best.$2;
        slack = 6;
        continue;
      }
      result.add(AyahVerdict(a, Verdict.wrong, best.$1));
      final l = candidates(a).first.length;
      if (i + 1 < ayahs.length) {
        final next = ayahs[i + 1];
        // Apakah ayat ini terlewat (tidak dibaca) atau dibaca tetapi salah?
        final skipped = _bestAlign(next, heard, pos, slack + l + 20);
        final readWrong = _bestAlign(next, heard, best.$2, 6);
        if (skipped.$1 > readWrong.$1 + 0.05) {
          slack = slack + l + 20;
        } else {
          pos = best.$2;
          slack = 6;
        }
      }
    }
    return result;
  }

  /// Semua bentuk teks ternormalisasi yang dianggap benar untuk satu ayat.
  static List<String> candidates(Ayah a) {
    final list = <String>[normalize(a.text)];
    if (_hasMuqattaah(a)) {
      final words = a.text.split(' ');
      final spelled = StringBuffer();
      for (final r in words.first.runes) {
        final name = _letterNames[r == 0x0671 ? 0x0627 : r];
        if (name != null) spelled.write(name);
      }
      list.add(normalize('$spelled ${words.skip(1).join(' ')}'));
    }
    return list;
  }
}
