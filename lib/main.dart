import 'package:flutter/material.dart';

import 'data/quran.dart';
import 'screens/home_screen.dart';
import 'screens/murajaah_screen.dart';
import 'services/model_store.dart';
import 'services/parent_report.dart';
import 'services/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    QuranData.load(),
    Settings.instance.load(),
    ParentReport.instance.load(),
  ]);
  // Bersihkan sisa rekaman/unduhan yang tertinggal (mis. aplikasi ditutup paksa).
  MurajaahController.deleteRecording();
  ModelStore.instance.cleanupPartial();
  runApp(const SambungAyatApp());
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
