import 'package:flutter/material.dart';

import '../utils/app_constants.dart';

/// Widget logo lingkaran konsentris + teks PindaiKu yang dipakai bersama
/// pada LoginScreen dan RegisterScreen (100% compile-time const).
class PindaiKuLogo extends StatelessWidget {
  const PindaiKuLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 150,
          height: 150,
          decoration: const BoxDecoration(
            color: AppConstants.logoCircleBg,
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: 105,
                height: 105,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(
                    BorderSide(color: AppConstants.accentCyan, width: 3),
                  ),
                ),
              ),
              Container(
                width: 82,
                height: 82,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(
                    BorderSide(color: AppConstants.darkSlate, width: 2.5),
                  ),
                ),
              ),
              const Icon(
                Icons.person_search_rounded,
                size: 56,
                color: AppConstants.darkSlate,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
            children: <InlineSpan>[
              TextSpan(
                text: 'Pindai',
                style: TextStyle(color: AppConstants.darkSlate),
              ),
              TextSpan(
                text: 'Ku',
                style: TextStyle(color: AppConstants.accentCyan),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Menampilkan dialog pembuatan folder baru yang dipakai bersama di HomeScreen
/// dan ScanNoteScreen, lengkap dengan pembersihan TextEditingController otomatis.
Future<String?> showCreateFolderDialog(
  BuildContext context, {
  String hintText = 'Contoh: Arsip, Keuangan, Pribadi',
  String confirmLabel = 'Simpan',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CreateFolderDialog(
      hintText: hintText,
      confirmLabel: confirmLabel,
    ),
  );
}

class _CreateFolderDialog extends StatefulWidget {
  final String hintText;
  final String confirmLabel;

  const _CreateFolderDialog({
    required this.hintText,
    required this.confirmLabel,
  });

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  final TextEditingController _folderController = TextEditingController();

  @override
  void dispose() {
    _folderController.dispose();
    super.dispose();
  }

  void _submit() {
    final String trimmed = _folderController.text.trim();
    Navigator.pop(context, trimmed.isEmpty ? null : trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: <Widget>[
          Icon(Icons.create_new_folder_outlined, color: AppConstants.accentCyan),
          SizedBox(width: 8),
          Text(
            'Buat Folder Baru',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: TextField(
        controller: _folderController,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Nama Folder',
          hintText: widget.hintText,
          border: AppConstants.inputBorder,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConstants.primaryBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
