import 'dart:math' as math;
import 'dart:typed_data';

/// Pecah rekaman panjang menjadi potongan ≤ 28 detik, memotong di bagian
/// paling hening (jeda/waqaf) agar kata tidak terpotong. Potongan yang
/// hanya berisi hening dibuang.
List<Float32List> splitOnPauses(Float32List pcm, {int sampleRate = 16000}) {
  final frame = sampleRate ~/ 50; // 20 ms
  final nFrames = pcm.length ~/ frame;
  if (nFrames == 0) return [];
  final rms = Float64List(nFrames);
  for (var f = 0; f < nFrames; f++) {
    var s = 0.0;
    final o = f * frame;
    for (var i = 0; i < frame; i++) {
      final v = pcm[o + i];
      s += v * v;
    }
    rms[f] = math.sqrt(s / frame);
  }
  final sorted = Float64List.fromList(rms)..sort();
  final floor = sorted[(nFrames * 0.1).floor()];
  final speechLevel = math.max(floor * 3, 0.004);

  final maxLen = 28 * 50; // frame
  final minLen = 12 * 50;
  const win = 7; // ±140 ms

  double energyAround(int f) {
    var s = 0.0;
    for (var k = math.max(0, f - win); k <= math.min(nFrames - 1, f + win); k++) {
      s += rms[k];
    }
    return s;
  }

  final chunks = <Float32List>[];
  var start = 0;
  while (start < nFrames) {
    int end;
    if (nFrames - start <= maxLen) {
      end = nFrames;
    } else {
      end = start + maxLen;
      var best = double.infinity;
      for (var f = start + minLen; f <= start + maxLen; f++) {
        final e = energyAround(f);
        if (e < best) {
          best = e;
          end = f;
        }
      }
    }
    // Apakah potongan berisi suara?
    var loud = 0;
    for (var f = start; f < end; f++) {
      if (rms[f] > speechLevel) loud++;
    }
    if (loud >= 15) {
      // ≥ 0,3 detik suara
      final s = start * frame;
      final e = end == nFrames ? pcm.length : end * frame;
      chunks.add(Float32List.sublistView(pcm, s, e));
    }
    start = end;
  }
  return chunks;
}
