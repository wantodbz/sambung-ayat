import 'package:flutter/material.dart';

import '../data/quran.dart';
import '../main.dart';
import '../services/matcher.dart';

/// Kartu satu ayat yang salah/tidak terbaca: teks benar, huruf salah merah.
class MistakeCard extends StatelessWidget {
  const MistakeCard({super.key, required this.v});
  final AyahVerdict v;

  /// Pecah teks ayat menjadi potongan biasa dan potongan merah.
  static List<TextSpan> _spans(AyahVerdict v) {
    final text = v.ayah.text;
    final wrong = v.wrongChars;
    if (wrong.isEmpty) return [TextSpan(text: text)];
    const red = TextStyle(
      color: AppColors.red,
      backgroundColor: Color(0x1FB3261E),
    );
    final spans = <TextSpan>[];
    var start = 0;
    var cur = wrong.contains(0);
    for (var i = 1; i <= text.length; i++) {
      final w = i < text.length && wrong.contains(i);
      if (i == text.length || w != cur) {
        spans.add(TextSpan(
            text: text.substring(start, i), style: cur ? red : null));
        start = i;
        cur = w;
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final q = QuranData.instance;
    final notRead = v.verdict == Verdict.notRead;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: notRead ? Colors.black26 : AppColors.orange, width: 1.5),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: notRead ? Colors.black12 : AppColors.orangeSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(notRead ? 'Tidak terbaca' : 'Salah',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: notRead ? Colors.black54 : AppColors.orangeDark)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'QS. ${q.surah(v.ayah.surah).latin} ayat ${v.ayah.ayah}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.greenDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
              notRead || v.wrongChars.isEmpty
                  ? 'Bacaan yang benar:'
                  : 'Bacaan yang benar (merah = bagian yang terdengar salah):',
              style: const TextStyle(fontSize: 12.5, color: Colors.black45)),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(children: _spans(v)),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: 24, height: 1.9, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}
