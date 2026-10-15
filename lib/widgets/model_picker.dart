import 'package:flutter/material.dart';

import '../main.dart';
import '../services/model_store.dart';
import '../services/settings.dart';

/// Daftar kedua model koreksi Murajaah: pilih, lihat status unduhan, hapus.
/// Model yang tidak dipilih tetap disimpan agar bisa bolak-balik tanpa
/// mengunduh ulang.
class ModelPicker extends StatefulWidget {
  const ModelPicker({super.key, this.onSelected});

  /// Dipanggil setelah pengguna memilih model.
  final ValueChanged<QuranModel>? onSelected;

  @override
  State<ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<ModelPicker> {
  final Map<QuranModel, int> _sizes = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    for (final m in QuranModel.values) {
      _sizes[m] = await ModelStore.instance.size(m);
    }
    if (mounted) setState(() {});
  }

  String _mb(int b) => '${(b / 1048576).toStringAsFixed(0)} MB';

  @override
  Widget build(BuildContext context) {
    final selected = Settings.instance.model;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final m in QuranModel.values)
          Card(
            elevation: 0,
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                  color: m == selected ? AppColors.orange : Colors.black12,
                  width: m == selected ? 2 : 1),
            ),
            child: ListTile(
              onTap: () async {
                await Settings.instance.setModel(m);
                if (mounted) setState(() {});
                widget.onSelected?.call(m);
              },
              leading: Icon(
                m == selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: m == selected ? AppColors.orange : Colors.black38,
              ),
              title: Text(
                  'Model ${m.label}${m == QuranModel.akurat ? ' (disarankan)' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${m.hint}\n'
                '${(_sizes[m] ?? 0) > 0 ? '✓ Sudah diunduh (${_mb(_sizes[m]!)})' : 'Belum diunduh'}',
              ),
              isThreeLine: true,
              trailing: (_sizes[m] ?? 0) > 0
                  ? IconButton(
                      tooltip: 'Hapus model',
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.red),
                      onPressed: () => _delete(m),
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  Future<void> _delete(QuranModel m) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus model ${m.label}?'),
        content: const Text(
            'Memori HP akan lega. Model bisa diunduh lagi kapan saja.'),
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
    await ModelStore.instance.delete(m);
    await _refresh();
  }
}
