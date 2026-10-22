// Uji pemotong rekaman: potongan langsung (sambil merekam) harus sama
// dengan pemotongan setelah rekaman selesai.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sambung_ayat/services/audio_split.dart';

/// Rekaman tiruan: bacaan (nada) 3–6 detik diselingi jeda 0,4–1,2 detik.
Int16List fakeRecitation(int seconds, {int seed = 1}) {
  final rnd = math.Random(seed);
  final out = Int16List(seconds * 16000);
  var i = 0;
  while (i < out.length) {
    final speech = (3 + rnd.nextDouble() * 3) * 16000;
    final pause = (0.4 + rnd.nextDouble() * 0.8) * 16000;
    for (var k = 0; k < speech && i < out.length; k++, i++) {
      out[i] = (9000 * math.sin(2 * math.pi * 220 * k / 16000) +
              rnd.nextInt(400) - 200)
          .round();
    }
    for (var k = 0; k < pause && i < out.length; k++, i++) {
      out[i] = rnd.nextInt(60) - 30;
    }
  }
  return out;
}

List<Int16List> splitLive(Int16List pcm, {int block = 1600}) {
  final s = LiveSplitter();
  final out = <Int16List>[];
  for (var o = 0; o < pcm.length; o += block) {
    out.addAll(s.add(Int16List.sublistView(pcm, o, math.min(pcm.length, o + block))));
  }
  out.addAll(s.finish());
  return out;
}

void main() {
  test('potongan langsung sama dengan potongan setelah selesai', () {
    final pcm = fakeRecitation(150);
    final batch = splitOnPauses(
        Float32List.fromList([for (final v in pcm) v / 32768.0]));
    final live = splitLive(pcm);
    expect(live.map((c) => c.length).toList(),
        batch.map((c) => c.length).toList());
    expect(live.fold<int>(0, (a, c) => a + c.length), pcm.length);
    for (var i = 0; i < live.length; i++) {
      expect(live[i].length, lessThanOrEqualTo(28 * 16000 + 320));
      if (i < live.length - 1) {
        expect(live[i].length, greaterThanOrEqualTo(12 * 16000));
      }
    }
  });

  test('ukuran blok rekaman tidak memengaruhi hasil', () {
    final pcm = fakeRecitation(95, seed: 7);
    final a = splitLive(pcm, block: 320).map((c) => c.length).toList();
    final b = splitLive(pcm, block: 7777).map((c) => c.length).toList();
    expect(a, b);
  });

  test('rekaman hening saja tidak menghasilkan potongan', () {
    final rnd = math.Random(3);
    final pcm = Int16List.fromList(
        List.generate(40 * 16000, (_) => rnd.nextInt(40) - 20));
    expect(splitLive(pcm), isEmpty);
  });
}
