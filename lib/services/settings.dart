import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'model_store.dart';
import 'reciters.dart';

/// Tingkat ketelitian pengecekan bacaan.
enum Strictness { longgar, normal, ketat }

extension StrictnessX on Strictness {
  String get label => switch (this) {
        Strictness.longgar => 'Longgar',
        Strictness.normal => 'Normal',
        Strictness.ketat => 'Ketat',
      };

  String get hint => switch (this) {
        Strictness.longgar =>
          'Cocok bila suara sering tidak tertangkap jelas (HP lama, ruangan ramai).',
        Strictness.normal => 'Pilihan seimbang untuk sebagian besar pengguna.',
        Strictness.ketat =>
          'Menuntut bacaan hampir persis. Kesalahan kecil lebih mudah terdeteksi.',
      };

  double get threshold => switch (this) {
        Strictness.longgar => 0.65,
        Strictness.normal => 0.75,
        Strictness.ketat => 0.85,
      };
}

class Settings {
  Settings._();
  static final Settings instance = Settings._();

  static const _kStrict = 'strictness';
  static const _kModel = 'quran_model';
  static const _kReciter = 'reciter';
  static const _kQuiet = 'quiet_seconds';

  /// Pilihan jeda tunggu Sambung Ayat (detik).
  static const quietChoices = [3, 4, 5, 6, 7];

  /// Sambung Ayat: lama diam (mis. lupa di tengah ayat) sebelum bacaan
  /// dinilai lalu lanjut otomatis.
  int quietSeconds = 5;

  /// Qari murottal terpilih (bisa didengarkan perubahannya oleh layar).
  final ValueNotifier<Reciter> reciterListenable =
      ValueNotifier<Reciter>(Reciter.aiman);
  Reciter get reciter => reciterListenable.value;
  Strictness strictness = Strictness.normal;
  // Versi web (iPhone/Safari) lebih lambat: bawaan model Cepat.
  QuranModel model = kIsWeb ? QuranModel.cepat : QuranModel.akurat;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final i = p.getInt(_kStrict);
    if (i != null && i >= 0 && i < Strictness.values.length) {
      strictness = Strictness.values[i];
    }
    final r = p.getString(_kReciter);
    for (final x in Reciter.values) {
      if (x.name == r) reciterListenable.value = x;
    }
    final m = p.getInt(_kModel);
    if (m != null && m >= 0 && m < QuranModel.values.length) {
      model = QuranModel.values[m];
    }
    final q = p.getInt(_kQuiet);
    if (q != null && quietChoices.contains(q)) quietSeconds = q;
  }

  Future<void> setQuietSeconds(int s) async {
    quietSeconds = s;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kQuiet, s);
  }

  Future<void> setReciter(Reciter r) async {
    reciterListenable.value = r;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kReciter, r.name);
  }

  Future<void> setModel(QuranModel m) async {
    model = m;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kModel, m.index);
  }

  Future<void> setStrictness(Strictness s) async {
    strictness = s;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kStrict, s.index);
  }
}
