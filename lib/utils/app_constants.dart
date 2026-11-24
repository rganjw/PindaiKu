import 'package:flutter/material.dart';

abstract final class AppConstants {
  // Warna utama aplikasi PindaiKu (100% identik dengan desain asli)
  static const Color primaryBlue = Color(0xFF1967D2);
  static const Color accentCyan = Color(0xFF00ACC1);
  static const Color darkSlate = Color(0xFF263238);
  static const Color logoCircleBg = Color(0xFFF3F6FA);
  static const Color textDark = Color(0xFF1A1A1A);
  static const Color scannerDarkBg = Color(0xFF1A1A1A);
  static const Color scannerCardBg = Color(0xFF2B2B2B);
  static const Color scannerLaserBlue = Color(0xFF29B6F6);
  static const Color folderIdleBg = Color(0xFFF0F0F0);
  static const Color notifAvatarBg = Color(0xFFE0F7FA);
  static const Color previewCanvasBg = Color(0xFFD9D9D9);

  // Nama folder standar
  static const String allFolders = 'Semua';
  static const String defaultFolder = 'Dokumen';

  // Border standar TextField yang dipakai di seluruh layar (Colors.grey.shade300 == 0xFFE0E0E0)
  static const OutlineInputBorder inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    borderSide: BorderSide(color: Color(0xFFE0E0E0)),
  );

  static const List<String> _indonesianMonths = <String>[
    'januari',
    'februari',
    'maret',
    'april',
    'mei',
    'juni',
    'juli',
    'agustus',
    'september',
    'oktober',
    'november',
    'desember',
  ];

  static String formatIndonesianDate(DateTime dt) {
    return '${dt.day} ${_indonesianMonths[dt.month - 1]} ${dt.year}';
  }
}
