// Uji koreksi bacaan: bagian yang salah ditampilkan sebagai pasangan
// "terdengar → seharusnya".
import 'package:flutter_test/flutter_test.dart';
import 'package:sambung_ayat/data/quran.dart';
import 'package:sambung_ayat/services/matcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => QuranData.load());

  test('kata yang salah: terdengar vs seharusnya', () {
    final a = QuranData.instance.rangeSurah(112)[1]; // ٱللَّهُ ٱلصَّمَدُ
    const raw = 'الله الاحد';
    final (norm, map) = ArabicMatcher.normalizeWithMap(raw);
    final (red, heard, corrections) =
        ArabicMatcher.explain(a.text, norm, map, raw, 0, 6, norm.length);
    expect(heard, raw);
    expect(corrections, hasLength(1));
    expect(corrections.single.heard, 'الاحد');
    expect(corrections.single.expected, a.text.split(' ').last);
    expect(red, isNotEmpty);
  });

  test('akhir ayat tidak terbaca: bagian itu "tidak terdengar"', () {
    final a = QuranData.instance.rangeSurah(112)[3]; // وَلَمۡ يَكُن لَّهُۥ …
    const raw = 'ولم يكن';
    final (norm, map) = ArabicMatcher.normalizeWithMap(raw);
    final (_, heard, corrections) =
        ArabicMatcher.explain(a.text, norm, map, raw, 0, 6, norm.length);
    expect(heard, raw);
    expect(corrections, hasLength(1));
    expect(corrections.single.heard, isEmpty);
    expect(corrections.single.expected, a.text.split(' ').skip(2).join(' '));
  });

  test('murajaah: tulisan terdengar disimpan per ayat, ayat terlewat ditandai',
      () {
    final ayahs = QuranData.instance.rangeSurah(112);
    // Ayat 2 terlewat, ayat lain dibaca benar (teks keluaran pengenal suara).
    const raw = 'قُلْ هُوَ اللَّهُ أَحَدٌ لَمْ يَلِدْ وَلَمْ يُولَدْ '
        'وَلَمْ يَكُنْ لَهُ كُفُوًا أَحَدٌ';
    final v = ArabicMatcher.review(ayahs, raw, 0.75);
    expect(v.map((x) => x.verdict).toList(), [
      Verdict.correct,
      isNot(Verdict.correct),
      Verdict.correct,
      Verdict.correct,
    ]);
  });
}
