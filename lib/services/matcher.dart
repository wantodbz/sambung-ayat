import 'dart:math' as math;

import '../data/quran.dart';

enum Verdict { correct, wrong, notRead }

/// Satu bagian bacaan yang salah: apa yang terdengar dan seharusnya apa.
class Correction {
  /// Tulisan yang terdengar oleh aplikasi ('' = tidak terdengar).
  final String heard;

  /// Tulisan ayat yang seharusnya dibaca.
  final String expected;
  const Correction(this.heard, this.expected);
}

/// Hasil koreksi satu ayat pada murajaah.
class AyahVerdict {
  final Ayah ayah;
  final Verdict verdict;
  final double similarity;

  /// Indeks karakter teks ayat yang diwarnai merah (hanya untuk [Verdict.wrong]).
  final Set<int> wrongChars;

  /// Tulisan yang terdengar untuk ayat ini (apa adanya dari pengenal suara).
  final String heard;

  /// Bagian yang salah: terdengar → seharusnya.
  final List<Correction> corrections;
  const AyahVerdict(this.ayah, this.verdict, this.similarity,
      [this.wrongChars = const {},
      this.heard = '',
      this.corrections = const []]);
}

/// Penyelarasan rinci satu ayat dengan bacaan terdengar (ternormalisasi).
class _Alignment {
  _Alignment(this.map, this.wrong, this.at, this.start, this.end);

  /// Huruf ayat ternormalisasi -> indeks karakter teks ayat asli.
  final List<int> map;

  /// Huruf ayat (ternormalisasi) yang terbaca lain atau tidak terdengar.
  final Set<int> wrong;

  /// Huruf ayat -> indeks huruf terdengar yang dipasangkan (-1 = tidak ada).
  final List<int> at;

  /// Rentang huruf terdengar yang dipakai ayat ini.
  final int start;
  final int end;
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

  static bool isMark(int r) =>
      (r >= 0x0610 && r <= 0x061A) ||
      (r >= 0x064B && r <= 0x065F) ||
      r == 0x0670 ||
      (r >= 0x06D6 && r <= 0x06ED) ||
      r == 0x0640;

  /// Normalisasi: hapus harakat & tanda waqaf, satukan bentuk huruf,
  /// hapus alif (karena rasm Utsmani sering membuang/menyisipkan alif),
  /// dan hapus spasi.
  static String normalize(String input) => normalizeWithMap(input).$1;

  /// Seperti [normalize], ditambah peta: indeks huruf ternormalisasi ->
  /// indeks karakter pada teks asli (untuk mewarnai huruf yang salah).
  static (String, List<int>) normalizeWithMap(String input) {
    final sb = StringBuffer();
    final map = <int>[];
    void put(int c, int i) {
      sb.writeCharCode(c);
      map.add(i);
    }

    for (var i = 0; i < input.length; i++) {
      final r = input.codeUnitAt(i);
      if (isMark(r)) continue;
      // Rasm Utsmani: waw + alif kecil dibaca/ditulis alif (الصلوة = الصلاة).
      if (r == 0x0648 &&
          i + 1 < input.length &&
          input.codeUnitAt(i + 1) == 0x0670) {
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
          put(0x0648, i);
          continue;
        case 0x0626: // ئ
        case 0x0649: // ى
        case 0x06CC: // ی
          put(0x064A, i);
          continue;
        case 0x0629: // ة
          put(0x0647, i);
          continue;
        case 0x06A9: // ک
          put(0x0643, i);
          continue;
      }
      if (r >= 0x0621 && r <= 0x064A) put(r, i);
    }
    return (sb.toString(), map);
  }

  /// Selaraskan huruf ayat [text] dengan [heard] (ternormalisasi) pada rentang
  /// [from]..[end]; awal boleh bergeser sampai [slack] huruf.
  static _Alignment _align(
      String text, String heard, int from, int slack, int end) {
    final (exp, map) = normalizeWithMap(text);
    final l = exp.length;
    final wrongNorm = <int>{};
    final at = List<int>.filled(l, -1);
    final e = math.min(end, heard.length);
    if (e <= from || l == 0) {
      for (var i = 0; i < l; i++) {
        wrongNorm.add(i);
      }
      return _Alignment(map, wrongNorm, at, from, math.max(from, e));
    }
    final s = heard.substring(from, e);
    final n = s.length;
    final d = List.generate(l + 1, (_) => List<int>.filled(n + 1, 0));
    for (var j = 0; j <= n; j++) {
      d[0][j] = j <= slack ? 0 : 2 * (j - slack);
    }
    for (var i = 1; i <= l; i++) {
      d[i][0] = i;
      final ca = exp.codeUnitAt(i - 1);
      final row = d[i];
      final up = d[i - 1];
      for (var j = 1; j <= n; j++) {
        var v = up[j - 1] + (ca == s.codeUnitAt(j - 1) ? 0 : 2);
        if (up[j] + 1 < v) v = up[j] + 1;
        if (row[j - 1] + 2 < v) v = row[j - 1] + 2;
        row[j] = v;
      }
    }
    var i = l;
    var j = n;
    while (i > 0) {
      if (j > 0) {
        final c = exp.codeUnitAt(i - 1) == s.codeUnitAt(j - 1) ? 0 : 2;
        if (d[i][j] == d[i - 1][j - 1] + c) {
          at[i - 1] = from + j - 1;
          if (c != 0) wrongNorm.add(i - 1);
          i--;
          j--;
          continue;
        }
        if (d[i][j] == d[i][j - 1] + 2) {
          j--;
          continue;
        }
      }
      wrongNorm.add(i - 1); // huruf ayat tidak terdengar
      i--;
    }
    return _Alignment(map, wrongNorm, at, from + j, e);
  }

  /// Indeks karakter pada [text] (teks ayat asli) yang perlu diwarnai merah:
  /// huruf yang terbaca lain atau tidak terdengar, beserta harakatnya.
  /// Bila separuh huruf atau lebih dalam satu kata salah, seluruh kata diwarnai.
  static Set<int> wrongChars(
          String text, String heard, int from, int slack, int end) =>
      _redChars(text, _align(text, heard, from, slack, end));

  /// Rincian koreksi satu ayat: huruf merah, tulisan yang terdengar untuk ayat
  /// ini, dan pasangan "terdengar → seharusnya" per bagian yang salah.
  /// [heard] adalah [heardRaw] yang sudah dinormalkan, [heardMap] petanya.
  static (Set<int>, String, List<Correction>) explain(
      String text,
      String heard,
      List<int> heardMap,
      String heardRaw,
      int from,
      int slack,
      int end) {
    final al = _align(text, heard, from, slack, end);
    return (
      _redChars(text, al),
      _rawSpan(heardRaw, heardMap, al.start, al.end),
      _corrections(text, al, heardRaw, heardMap),
    );
  }

  /// Potongan [raw] untuk huruf ternormalisasi [s]..[e], diperluas ke kata utuh.
  static String _rawSpan(String raw, List<int> map, int s, int e) {
    if (s >= e || s >= map.length) return '';
    var rs = map[s];
    var re = map[math.min(e, map.length) - 1] + 1;
    while (rs > 0 && raw.codeUnitAt(rs - 1) != 0x20) {
      rs--;
    }
    while (re < raw.length && raw.codeUnitAt(re) != 0x20) {
      re++;
    }
    return raw.substring(rs, re).trim();
  }

  /// Kelompokkan kata ayat yang salah (berurutan) dan pasangkan dengan
  /// tulisan yang terdengar di posisi yang sama.
  static List<Correction> _corrections(
      String text, _Alignment al, String raw, List<int> rawMap) {
    // Kata ayat: (awal, akhir) karakter asli, (awal, akhir) huruf ternormalisasi.
    final words = <(int, int, int, int)>[];
    var k = 0;
    var ws = 0;
    while (ws < text.length) {
      var we = text.indexOf(' ', ws);
      if (we < 0) we = text.length;
      final k0 = k;
      while (k < al.map.length && al.map[k] < we) {
        k++;
      }
      if (we > ws) words.add((ws, we, k0, k));
      ws = we + 1;
    }
    bool isBad(int w) {
      for (var x = words[w].$3; x < words[w].$4; x++) {
        if (al.wrong.contains(x)) return true;
      }
      return false;
    }

    bool isGood(int x) => al.at[x] >= 0 && !al.wrong.contains(x);

    final out = <Correction>[];
    var w = 0;
    while (w < words.length) {
      if (!isBad(w)) {
        w++;
        continue;
      }
      var last = w;
      var x = w + 1;
      // Gabungkan kata salah berurutan (kata tanpa huruf, mis. tanda waqaf,
      // tidak memutus kelompok).
      while (x < words.length && (isBad(x) || words[x].$3 == words[x].$4)) {
        if (isBad(x)) last = x;
        x++;
      }
      var hs = al.start;
      for (var y = words[w].$3 - 1; y >= 0; y--) {
        if (isGood(y)) {
          hs = al.at[y] + 1;
          break;
        }
      }
      var he = al.end;
      for (var y = words[last].$4; y < al.at.length; y++) {
        if (isGood(y)) {
          he = al.at[y];
          break;
        }
      }
      out.add(Correction(_rawSpan(raw, rawMap, hs, he),
          text.substring(words[w].$1, words[last].$2)));
      w = last + 1;
    }
    return out;
  }

  static Set<int> _redChars(String text, _Alignment al) {
    final map = al.map;
    final wrongNorm = al.wrong;
    // Petakan ke teks asli, per kata.
    final result = <int>{};
    var k = 0; // indeks huruf ternormalisasi
    var ws = 0;
    while (ws < text.length) {
      var we = text.indexOf(' ', ws);
      if (we < 0) we = text.length;
      final letters = <int>[];
      while (k < map.length && map[k] < we) {
        letters.add(k);
        k++;
      }
      final bad = letters.where(wrongNorm.contains).toList();
      if (letters.isNotEmpty && bad.length * 2 >= letters.length) {
        for (var c = ws; c < we; c++) {
          result.add(c);
        }
      } else {
        for (final b in bad) {
          var c = map[b];
          result.add(c);
          c++;
          while (c < we && isMark(text.codeUnitAt(c))) {
            result.add(c);
            c++;
          }
        }
      }
      ws = we + 1;
    }
    return result;
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

  /// Periksa seluruh bacaan [heardRaw] (teks apa adanya dari pengenal suara)
  /// terhadap [ayahs].
  static List<AyahVerdict> review(
      List<Ayah> ayahs, String heardRaw, double threshold) {
    final result = <AyahVerdict>[];
    if (ayahs.isEmpty) return result;
    final (heard, heardMap) = normalizeWithMap(heardRaw);
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
      final l = candidates(a).first.length;
      // Apakah ayat ini terlewat (tidak dibaca) atau dibaca tetapi salah?
      var skippedThis = false;
      if (i + 1 < ayahs.length) {
        final next = ayahs[i + 1];
        final skipped = _bestAlign(next, heard, pos, slack + l + 20);
        final readWrong = _bestAlign(next, heard, best.$2, 6);
        skippedThis = skipped.$1 > readWrong.$1 + 0.05;
      }
      if (skippedThis) {
        // Bacaan sesudahnya cocok dengan ayat berikutnya: ayat ini terlewat.
        result.add(AyahVerdict(a, Verdict.notRead, best.$1));
        slack = slack + l + 20;
        continue;
      }
      final (red, heardText, corrections) =
          explain(a.text, heard, heardMap, heardRaw, pos, slack, best.$2);
      result.add(AyahVerdict(
          a, Verdict.wrong, best.$1, red, heardText, corrections));
      pos = best.$2;
      slack = 6;
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
