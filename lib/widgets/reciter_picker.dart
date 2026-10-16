import 'package:flutter/material.dart';

import '../main.dart';
import '../platform/platform.dart';
import '../services/audio_store.dart';
import '../services/reciters.dart';
import '../services/settings.dart';

/// Daftar qari murottal: pilih, lihat audio yang tersimpan, hapus.
/// Audio qari yang tidak dipilih tetap disimpan sampai dihapus pengguna.
class ReciterPicker extends StatefulWidget {
  const ReciterPicker({super.key, this.onChanged});

  /// Dipanggil setelah qari dipilih atau audionya dihapus.
  final VoidCallback? onChanged;

  @override
  State<ReciterPicker> createState() => _ReciterPickerState();
}

class _ReciterPickerState extends State<ReciterPicker> {
  final Map<Reciter, (int, int)> _info = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    // Versi web memutar murottal langsung dari internet (tidak ada simpanan).
    if (streamsAudio) return;
    for (final r in Reciter.values) {
      try {
        _info[r] = await AudioStore.instance.summary(r);
      } catch (_) {
        _info[r] = (0, 0);
      }
    }
    if (mounted) setState(() {});
  }

  String _mb(int b) =>
      b < 1048576 ? '< 1 MB' : '${(b / 1048576).toStringAsFixed(0)} MB';

  @override
  Widget build(BuildContext context) {
    final selected = Settings.instance.reciter;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final r in Reciter.values)
          Card(
            elevation: 0,
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                  color: r == selected ? AppColors.orange : Colors.black12,
                  width: r == selected ? 2 : 1),
            ),
            child: ListTile(
              onTap: () async {
                await Settings.instance.setReciter(r);
                if (mounted) setState(() {});
                widget.onChanged?.call();
              },
              leading: Icon(
                r == selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: r == selected ? AppColors.orange : Colors.black38,
              ),
              title: Text(r.label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: streamsAudio ? null : Text(_status(r)),
              trailing: !streamsAudio && (_info[r]?.$2 ?? 0) > 0
                  ? IconButton(
                      tooltip: 'Hapus semua audio qari ini',
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.red),
                      onPressed: () => _delete(r),
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  String _status(Reciter r) {
    final info = _info[r];
    if (info == null) return 'Memeriksa…';
    final (full, bytes) = info;
    if (bytes == 0) return 'Belum ada audio tersimpan';
    return '✓ Tersimpan: $full surat lengkap • ${_mb(bytes)}';
  }

  Future<void> _delete(Reciter r) async {
    final bytes = _info[r]?.$2 ?? 0;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus audio qari ini?'),
        content: Text('Semua audio ${r.label} (${_mb(bytes)}) akan dihapus. '
            'Audio bisa diunduh lagi kapan saja.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (yes != true) return;
    await AudioStore.instance.deleteAll(r);
    await _refresh();
    widget.onChanged?.call();
  }
}
