// Uji alur Sambung Ayat dengan pengenal suara & pemutar tiruan:
// bacaan salah/tidak terbaca tetap lanjut, hitung mundur 15 detik hanya
// sampai suara bacaan terdengar, diam 3 detik setelah membaca langsung
// lanjut, dan koreksi ditampilkan di akhir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sambung_ayat/data/quran.dart';
import 'package:sambung_ayat/platform/platform.dart';
import 'package:sambung_ayat/screens/session_controller.dart';
import 'package:sambung_ayat/screens/session_screen.dart';
import 'package:sambung_ayat/services/matcher.dart';
import 'package:sambung_ayat/services/parent_report.dart';
import 'package:sambung_ayat/services/reciters.dart';
import 'package:sambung_ayat/services/settings.dart';
import 'package:sambung_ayat/widgets/mistake_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeEngine extends SpeechEngine {
  int session = 0;
  bool listening = false;

  @override
  Future<bool> init() async => true;

  @override
  Future<void> start() async {
    listening = true;
    session++;
  }

  @override
  Future<void> stop() async {
    listening = false;
  }

  @override
  bool get isListening => listening;

  void say(String text, {bool isFinal = true}) =>
      onResult?.call(text, isFinal, session);
}

class FakePlayer extends MurottalPlayer {
  final played = <String>[];

  @override
  Future<void> play(int surah, int ayah) async {
    played.add('$surah:$ayah');
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

SessionController makeController(FakeEngine e, FakePlayer p) =>
    SessionController(
      mode: SessionMode.sambungAyat,
      ayahs: QuranData.instance.rangeSurah(112), // Al-Ikhlas, 4 ayat
      threshold: 0.75,
      title: 'QS. Al-Ikhlas',
      engine: e,
      player: p,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await QuranData.load();
    await Settings.instance.load();
    await ParentReport.instance.load();
  });

  testWidgets('salah dan tidak terbaca tetap lanjut, dikoreksi di akhir',
      (tester) async {
    final e = FakeEngine();
    final p = FakePlayer();
    final c = makeController(e, p);
    unawaited(c.start());

    // HP: basmalah + ayat 1 (masing-masing 2 detik), lalu giliran ayat 2.
    await tester.pump(const Duration(seconds: 5));
    expect(p.played, ['1:1', '112:1']);
    expect(c.phase, Phase.listening);
    expect(c.current!.ayah, 2);

    // Ayat 2 dibaca salah → dicatat, sesi tetap lanjut.
    e.say('قل أعوذ برب الفلق');
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.phase, Phase.wrong);
    expect(c.verdicts.single.verdict, Verdict.wrong);
    expect(c.verdicts.single.wrongChars, isNotEmpty);

    await tester.pump(const Duration(seconds: 2));
    expect(c.phase, Phase.playing);
    expect(p.played.last, '112:3');

    await tester.pump(const Duration(seconds: 3));
    expect(c.phase, Phase.listening);
    expect(c.current!.ayah, 4);

    // Diam: hitung mundur berjalan…
    await tester.pump(const Duration(seconds: 10));
    expect(c.phase, Phase.listening);
    expect(c.countdown, inInclusiveRange(4, 6));

    // …dan setelah 15 detik ayat dicatat tidak terbaca, sesi selesai.
    await tester.pump(const Duration(seconds: 6));
    expect(c.verdicts.last.verdict, Verdict.notRead);
    await tester.pump(const Duration(seconds: 3));
    expect(c.phase, Phase.finished);
    expect(c.verdicts.map((v) => v.verdict).toList(),
        [Verdict.wrong, Verdict.notRead]);
    expect(c.mistakes.length, 2);
    expect(c.recordedSurahs, isEmpty); // ada salah: tidak masuk laporan
    c.dispose();
  });

  testWidgets('setelah membaca, diam 3 detik langsung lanjut (tanpa tampilan)',
      (tester) async {
    final e = FakeEngine();
    final p = FakePlayer();
    final c = makeController(e, p);
    unawaited(c.start());
    await tester.pump(const Duration(seconds: 5));
    expect(c.current!.ayah, 2);
    expect(c.voiceHeard, isFalse);

    // Membaca terus-menerus 8 detik (hasil sementara berubah tiap detik):
    // tidak terpotong.
    for (var i = 0; i < 8; i++) {
      e.say(i.isEven ? 'الله' : 'اللهُ', isFinal: false);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(c.voiceHeard, isTrue);
    expect(c.phase, Phase.listening);

    // Masih bersuara (mis. mad panjang) tanpa kata baru 5 detik: tidak terpotong.
    for (var i = 0; i < 5; i++) {
      e.onSound?.call();
      await tester.pump(const Duration(seconds: 1));
    }
    expect(c.phase, Phase.listening);
    expect(c.verdicts, isEmpty);

    // Berhenti (bacaan belum selesai): 2 detik setelah suara terakhir
    // masih menunggu…
    await tester.pump(const Duration(seconds: 1));
    expect(c.phase, Phase.listening);
    // …3 detik diam → dicatat salah dan langsung lanjut.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(c.verdicts.single.verdict, Verdict.wrong);
    await tester.pump(const Duration(seconds: 2));
    expect(c.phase, Phase.playing);
    expect(p.played.last, '112:3');

    await tester.pump(const Duration(seconds: 3));
    expect(c.current!.ayah, 4);
    e.say('ولم يكن له كفوا أحد');
    await tester.pump(const Duration(seconds: 3));
    expect(c.phase, Phase.finished);
    expect(c.verdicts.map((v) => v.verdict).toList(),
        [Verdict.wrong, Verdict.correct]);
    expect(c.recordedSurahs, isEmpty);
    c.dispose();
  });

  testWidgets('bising terus terbaca sebagai kata: tetap selesai (batas aman)',
      (tester) async {
    final e = FakeEngine();
    final p = FakePlayer();
    final c = makeController(e, p);
    unawaited(c.start());
    await tester.pump(const Duration(seconds: 5));
    expect(c.current!.ayah, 2);
    // Hasil sementara terus berubah tiap detik (mis. suara TV/kipas).
    // Ayat 2 berisi 8 huruf → batas aman 20 + 3,2 = 23,2 detik.
    for (var i = 0; i < 22; i++) {
      e.say(i.isEven ? 'الله' : 'اللهُ', isFinal: false);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(c.phase, Phase.listening);
    for (var i = 0; i < 3; i++) {
      e.say(i.isEven ? 'الله' : 'اللهُ', isFinal: false);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(c.verdicts.single.verdict, Verdict.wrong);
    c.dispose();
    await tester.pump(const Duration(seconds: 5)); // habiskan timer tersisa
  });

  testWidgets('HP tanpa hasil sementara: diam 3 detik setelah hasil terakhir',
      (tester) async {
    final e = FakeEngine();
    final p = FakePlayer();
    final c = makeController(e, p);
    unawaited(c.start());
    await tester.pump(const Duration(seconds: 5));
    e.say('الله'); // hasil final pertama (belum selesai)
    await tester.pump(const Duration(milliseconds: 2500));
    e.say('قل'); // masih membaca: hasil final berikutnya
    await tester.pump(const Duration(milliseconds: 2500));
    expect(c.phase, Phase.listening);
    await tester.pump(const Duration(seconds: 1));
    expect(c.verdicts.single.verdict, Verdict.wrong);
    c.dispose();
    await tester.pump(const Duration(seconds: 5)); // habiskan timer tersisa
  });

  testWidgets('semua benar langsung lanjut dan tercatat di laporan',
      (tester) async {
    final e = FakeEngine();
    final p = FakePlayer();
    final c = makeController(e, p);
    unawaited(c.start());
    await tester.pump(const Duration(seconds: 5));
    e.say('الله الصمد');
    await tester.pump(const Duration(seconds: 4));
    expect(c.current!.ayah, 4);
    expect(c.voiceHeard, isFalse); // giliran baru: hitung mundur dari awal
    expect(c.countdown, greaterThanOrEqualTo(13));
    e.say('ولم يكن له كفوا أحد');
    await tester.pump(const Duration(seconds: 3));
    expect(c.phase, Phase.finished);
    expect(c.mistakes, isEmpty);
    expect(c.correctCount, 2);
    expect(c.recordedSurahs, [112]);
    c.dispose();
  });

  testWidgets('layar sesi & hasil tampil di ukuran HP tanpa galat tata letak',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final e = FakeEngine();
    final p = FakePlayer();
    final c = makeController(e, p);
    await tester.pumpWidget(MaterialApp(home: SessionScreen(controller: c)));
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Selesai membaca'), findsOneWidget);
    expect(find.text('Giliran Anda: bacalah ayat 2'), findsOneWidget);

    expect(find.byKey(const Key('countdown')), findsOneWidget);

    // Ketuk "Selesai membaca" tanpa bacaan → tidak terbaca, lanjut.
    await tester.tap(find.text('Selesai membaca'));
    await tester.pump(const Duration(seconds: 6));
    expect(c.current!.ayah, 4);
    expect(find.byKey(const Key('countdown')), findsOneWidget);

    // Suara terdengar → hitung mundur hilang dari layar.
    e.say('ولم يكن', isFinal: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('countdown')), findsNothing);
    expect(find.text('Mendengarkan bacaan…'), findsOneWidget);

    // Berhenti di tengah ayat: 3 detik diam → otomatis lanjut (selesai).
    await tester.pump(const Duration(seconds: 2));
    expect(c.phase, Phase.listening);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(c.phase, Phase.finished);
    expect(c.verdicts.last.verdict, Verdict.wrong);
    expect(c.verdicts.last.wrongChars, isNotEmpty);
    expect(find.text('2 ayat perlu diperbaiki'), findsOneWidget);
    expect(find.text('Benar 0 dari 2 ayat yang Anda baca'), findsOneWidget);
    expect(find.byType(MistakeCard), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox());
  });

  test('folder EveryAyah tiap qari', () {
    expect(Reciter.values.map((r) => r.folder).toSet().length, 5);
    for (final r in Reciter.values) {
      expect(r.baseUrl, startsWith('https://everyayah.com/data/'));
      expect(r.baseUrl, endsWith('_64kbps/'));
    }
  });
}
