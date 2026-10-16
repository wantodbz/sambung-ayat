// Uji alur Sambung Ayat dengan pengenal suara & pemutar tiruan:
// bacaan salah/tidak terbaca tetap lanjut, hitung mundur 15 detik hanya
// sampai suara bacaan terdengar, dan koreksi ditampilkan di akhir.
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

  testWidgets('hitung mundur hilang setelah suara terdengar; semua benar',
      (tester) async {
    final e = FakeEngine();
    final p = FakePlayer();
    final c = makeController(e, p);
    unawaited(c.start());
    await tester.pump(const Duration(seconds: 5));
    expect(c.current!.ayah, 2);
    expect(c.voiceHeard, isFalse);

    // 10 detik diam, lalu bacaan mulai terdengar (hasil sementara).
    await tester.pump(const Duration(seconds: 10));
    expect(c.countdown, lessThanOrEqualTo(6));
    e.say('الله', isFinal: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.voiceHeard, isTrue);

    // Setelah ada suara tidak ada batas waktu: 60 detik tetap menunggu.
    await tester.pump(const Duration(seconds: 60));
    expect(c.phase, Phase.listening);
    expect(c.verdicts, isEmpty);

    e.say('الله الصمد');
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.verdicts.last.verdict, Verdict.correct);

    // Giliran berikutnya: hitung mundur muncul lagi dari awal.
    await tester.pump(const Duration(seconds: 4));
    expect(c.phase, Phase.listening);
    expect(c.current!.ayah, 4);
    expect(c.voiceHeard, isFalse);
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

    // Berhenti di tengah ayat: tetap menunggu sampai "Selesai membaca".
    await tester.pump(const Duration(seconds: 30));
    expect(c.phase, Phase.listening);
    await tester.tap(find.text('Selesai membaca'));
    await tester.pump(const Duration(seconds: 3));
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
