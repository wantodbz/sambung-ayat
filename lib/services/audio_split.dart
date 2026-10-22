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

/// Pemotong langsung untuk rekaman yang sedang berjalan: menerima PCM 16-bit
/// sedikit demi sedikit dan mengeluarkan potongan ≤ [maxSec] detik yang
/// dipotong di bagian paling hening, dengan aturan yang sama seperti
/// [splitOnPauses]. Dengan begitu potongan bisa diperiksa sambil anak masih
/// membaca. Potongan yang hanya berisi hening dibuang.
class LiveSplitter {
  LiveSplitter({this.sampleRate = 16000, this.maxSec = 28, this.minSec = 12});

  final int sampleRate;
  final int maxSec;
  final int minSec;

  static const int _win = 7; // ±140 ms

  int get _frame => sampleRate ~/ 50; // 20 ms
  int get _maxLen => maxSec * 50;
  int get _minLen => minSec * 50;

  Int16List _buf = Int16List(16000 * 32);
  int _len = 0; // jumlah sampel yang belum dikeluarkan
  final List<double> _rms = []; // RMS tiap bingkai utuh di _buf
  final List<double> _allRms = []; // seluruh rekaman (taksiran bising)

  /// Tambahkan sampel; kembalikan potongan yang sudah siap (bisa kosong).
  List<Int16List> add(Int16List samples) {
    if (_len + samples.length > _buf.length) {
      final bigger = Int16List(math.max(_buf.length * 2, _len + samples.length));
      bigger.setRange(0, _len, _buf);
      _buf = bigger;
    }
    _buf.setRange(_len, _len + samples.length, samples);
    _len += samples.length;
    _frames();
    final out = <Int16List>[];
    // Tunggu sampai jendela ±140 ms di sekitar batas terjauh tersedia utuh,
    // agar titik potong sama persis dengan splitOnPauses.
    while (_rms.length > _maxLen + _win) {
      _emit(_bestCut(), out);
    }
    return out;
  }

  /// Rekaman selesai: kembalikan sisa potongan.
  List<Int16List> finish() {
    _frames();
    final out = <Int16List>[];
    while (_rms.length > _maxLen) {
      _emit(_bestCut(), out);
    }
    if (_len > 0) _emit(_rms.length, out, all: true);
    return out;
  }

  void _frames() {
    final frame = _frame;
    while ((_rms.length + 1) * frame <= _len) {
      final o = _rms.length * frame;
      var s = 0.0;
      for (var i = 0; i < frame; i++) {
        final v = _buf[o + i] / 32768.0;
        s += v * v;
      }
      final r = math.sqrt(s / frame);
      _rms.add(r);
      _allRms.add(r);
    }
  }

  double _energyAround(int f) {
    var s = 0.0;
    final hi = math.min(_rms.length - 1, f + _win);
    for (var k = math.max(0, f - _win); k <= hi; k++) {
      s += _rms[k];
    }
    return s;
  }

  int _bestCut() {
    var end = _maxLen;
    var best = double.infinity;
    for (var f = _minLen; f <= _maxLen; f++) {
      final e = _energyAround(f);
      if (e < best) {
        best = e;
        end = f;
      }
    }
    return end;
  }

  /// Keluarkan bingkai [0, end) — atau seluruh sisa bila [all] — sebagai
  /// potongan bila berisi suara, lalu buang dari penampung.
  void _emit(int end, List<Int16List> out, {bool all = false}) {
    final sorted = List<double>.of(_allRms)..sort();
    final floor = sorted.isEmpty ? 0.0 : sorted[(sorted.length * 0.1).floor()];
    final speechLevel = math.max(floor * 3, 0.004);
    var loud = 0;
    for (var f = 0; f < end; f++) {
      if (_rms[f] > speechLevel) loud++;
    }
    final n = all ? _len : end * _frame;
    if (loud >= 15) out.add(Int16List.fromList(Int16List.sublistView(_buf, 0, n)));
    _buf.setRange(0, _len - n, _buf, n);
    _len -= n;
    _rms.removeRange(0, end);
  }
}
