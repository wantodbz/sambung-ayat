/// Pilihan qari murottal (audio per ayat dari EveryAyah.com, 64 kbps).
enum Reciter { aiman, hushari, ayyub, hudzaifi, bashfar }

extension ReciterX on Reciter {
  /// Nama lengkap untuk daftar pilihan.
  String get label => switch (this) {
        Reciter.aiman => 'Syaikh Aiman Rusydi Suwaid',
        Reciter.hushari => 'Syaikh Mahmud Khalil Al-Hushari',
        Reciter.ayyub => 'Syaikh Muhammad Ayyub',
        Reciter.hudzaifi => 'Syaikh Ali Al-Hudzaifi',
        Reciter.bashfar => 'Syaikh Abdullah Ali Bashfar',
      };

  /// Nama singkat untuk pesan di layar sesi.
  String get short => switch (this) {
        Reciter.aiman => 'Syaikh Aiman Suwaid',
        Reciter.hushari => 'Syaikh Al-Hushari',
        Reciter.ayyub => 'Syaikh Muhammad Ayyub',
        Reciter.hudzaifi => 'Syaikh Al-Hudzaifi',
        Reciter.bashfar => 'Syaikh Abdullah Bashfar',
      };

  /// Nama folder di EveryAyah.com.
  String get folder => switch (this) {
        Reciter.aiman => 'Ayman_Sowaid_64kbps',
        Reciter.hushari => 'Husary_64kbps',
        Reciter.ayyub => 'Muhammad_Ayyoub_64kbps',
        Reciter.hudzaifi => 'Hudhaify_64kbps',
        Reciter.bashfar => 'Abdullah_Basfar_64kbps',
      };

  /// Folder penyimpanan di HP. Aiman Suwaid memakai folder lama agar audio
  /// yang sudah diunduh di versi sebelumnya tetap terpakai.
  String get dirName => switch (this) {
        Reciter.aiman => 'ayman_suwaid',
        Reciter.hushari => 'husary',
        Reciter.ayyub => 'muhammad_ayyoub',
        Reciter.hudzaifi => 'hudhaify',
        Reciter.bashfar => 'abdullah_basfar',
      };

  String get baseUrl => 'https://everyayah.com/data/$folder/';

  /// Folder cadangan bila satu berkas tidak ada di folder utama
  /// (mis. Muhammad Ayyub 64 kbps tidak memiliki Al-Qasas ayat 87).
  List<String> get fallbackFolders => switch (this) {
        Reciter.ayyub => const [
            'Muhammad_Ayyoub_128kbps',
            'Muhammad_Ayyoub_32kbps',
          ],
        _ => const [],
      };

  /// Semua alamat yang dicoba untuk satu berkas, berurutan.
  List<String> urlsFor(String fileName) => [
        for (final f in [folder, ...fallbackFolders])
          'https://everyayah.com/data/$f/$fileName',
      ];
}
