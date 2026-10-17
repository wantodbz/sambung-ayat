import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';

import 'data/quran.dart';
import 'screens/home_screen.dart';
import 'screens/murajaah_screen.dart';
import 'services/parent_report.dart';
import 'services/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerLicenses();
  await Future.wait([
    QuranData.load(),
    Settings.instance.load(),
    ParentReport.instance.load(),
  ]);
  if (!kIsWeb && Platform.isIOS) await _configureIosAudio();
  // Bersihkan sisa rekaman/unduhan yang tertinggal (mis. aplikasi ditutup paksa).
  MurajaahController.deleteRecording();
  runApp(const SambungAyatApp());
}

/// Lisensi konten yang bukan paket Dart (tampil di halaman Lisensi).
void _registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Teks Al-Qur\'an (quran-json)'],
      'Teks Al-Qur\'an Rasm Utsmani dari The Noble Qur\'an Encyclopedia '
      '(QuranEnc.com), melalui paket quran-json (github.com/risan/quran-json).\n\n'
      'Lisensi: Creative Commons Attribution 4.0 International (CC BY 4.0)\n'
      'https://creativecommons.org/licenses/by/4.0/',
    );
    yield const LicenseEntryWithLineBreaks(
      ['Model Whisper Qur\'an (Tarteel AI)'],
      'Model tarteel-ai/whisper-tiny-ar-quran dan '
      'tarteel-ai/whisper-base-ar-quran, dikonversi ke format ggml '
      '(kuantisasi q8_0) untuk aplikasi ini.\n\n'
      'Lisensi: Apache License 2.0\n'
      'https://www.apache.org/licenses/LICENSE-2.0',
    );
  });
}

/// iPhone: putar murottal lewat speaker (bukan speaker telepon) walaupun
/// mikrofon sedang/baru saja dipakai.
Future<void> _configureIosAudio() async {
  try {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.defaultToSpeaker |
              AVAudioSessionCategoryOptions.allowBluetooth,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
    ));
  } catch (_) {}
}

class AppColors {
  static const green = Color(0xFF0E5C46);
  static const greenDark = Color(0xFF083D2E);
  static const orange = Color(0xFFF28C28);
  static const orangeDark = Color(0xFFB85C0A);
  static const orangeSoft = Color(0xFFFDE7D2);
  static const cream = Color(0xFFF5FAF6);
  static const red = Color(0xFFB3261E);
}

class SambungAyatApp extends StatelessWidget {
  const SambungAyatApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.green,
      primary: AppColors.green,
      secondary: AppColors.orange,
      surface: AppColors.cream,
    );
    return MaterialApp(
      title: 'Sambung Ayat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: AppColors.cream,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.green,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
