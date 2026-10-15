import 'dart:io';
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
