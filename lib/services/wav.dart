import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Membaca WAV PCM 16-bit (mono/stereo) menjadi float -1..1, mono.
Future<Float32List> readWavMono(String path) async {
  final bytes = await File(path).readAsBytes();
  final bd = ByteData.sublistView(bytes);
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('Berkas rekaman bukan WAV.');
  }
  var channels = 1;
  var bits = 16;
  var pos = 12;
  while (pos + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    var size = bd.getUint32(pos + 4, Endian.little);
    final body = pos + 8;
    if (id == 'fmt ') {
      channels = bd.getUint16(body + 2, Endian.little);
      bits = bd.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      // Sebagian perekam menulis ukuran 0/maks saat streaming; pakai sisa berkas.
      if (size == 0 || body + size > bytes.length) size = bytes.length - body;
      if (bits != 16) throw FormatException('WAV $bits-bit belum didukung.');
      final frames = size ~/ (2 * channels);
      final out = Float32List(frames);
      for (var i = 0; i < frames; i++) {
        var sum = 0;
        for (var c = 0; c < channels; c++) {
          sum += bd.getInt16(body + (i * channels + c) * 2, Endian.little);
        }
        out[i] = sum / (32768.0 * channels);
      }
      return out;
    }
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('Data audio tidak ditemukan.');
}

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
