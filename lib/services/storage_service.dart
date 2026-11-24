import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/note_model.dart';

typedef ActiveUser = ({String name, String email});

class StorageService {
  StorageService._internal();
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;

  static const String _notesKey = 'pindaiku_notes_v2';
  static const String _foldersKey = 'pindaiku_folders_v1';
  static const String _userNameKey = 'pindaiku_user_name';
  static const String _userEmailKey = 'pindaiku_user_email';
  static const String _userPassKey = 'pindaiku_user_pass';
  static const String _isLoggedInKey = 'pindaiku_is_logged_in';
  static const String _defaultFolder = 'Dokumen';

  static SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> get _prefs async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();

  @visibleForTesting
  static void resetCache() {
    _cachedPrefs = null;
  }

  Future<void> registerUser(String name, String email, String password) async {
    final prefs = await _prefs;
    await prefs.setString(_userNameKey, name.trim());
    await prefs.setString(_userEmailKey, email.trim());
    await prefs.setString(_userPassKey, password);
    // Pastikan pengguna harus login terlebih dahulu setelah mendaftar
    await prefs.setBool(_isLoggedInKey, false);
  }

  /// Memperbarui nama tampilan tanpa menimpa email maupun kata sandi pengguna.
  Future<void> updateUserName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final prefs = await _prefs;
    await prefs.setString(_userNameKey, trimmed);
  }

  Future<String?> loginUser(String email, String password) async {
    final prefs = await _prefs;
    final savedEmail = prefs.getString(_userEmailKey);
    final savedPass = prefs.getString(_userPassKey);

    // Wajib daftar terlebih dahulu jika belum ada akun tersimpan
    if (savedEmail == null || savedEmail.isEmpty) {
      return 'Akun belum terdaftar! Silakan tekan Daftar terlebih dahulu.';
    }

    if (savedEmail == email.trim() && savedPass == password) {
      await prefs.setBool(_isLoggedInKey, true);
      return null; // Berhasil masuk
    }
    return 'Email atau kata sandi salah!';
  }

  Future<ActiveUser?> getActiveUser() async {
    final prefs = await _prefs;
    final isLoggedIn = prefs.getBool(_isLoggedInKey) ?? false;
    if (!isLoggedIn) return null;

    final name = prefs.getString(_userNameKey) ?? 'Jose';
    final email = prefs.getString(_userEmailKey) ?? '';
    return (name: name, email: email);
  }

  Future<void> logoutUser() async {
    final prefs = await _prefs;
    await prefs.setBool(_isLoggedInKey, false);
  }

  Future<List<String>> getFolders() async {
    final prefs = await _prefs;
    final List<String>? folders = prefs.getStringList(_foldersKey);
    if (folders == null || folders.isEmpty) {
      return <String>[_defaultFolder];
    }
    return List<String>.of(folders);
  }

  Future<void> saveFolder(String folderName) async {
    final trimmed = folderName.trim();
    if (trimmed.isEmpty) return;
    final prefs = await _prefs;
    final existing = prefs.getStringList(_foldersKey);
    final folders = (existing == null || existing.isEmpty)
        ? <String>[_defaultFolder]
        : List<String>.of(existing);

    if (!folders.contains(trimmed)) {
      folders.add(trimmed);
      await prefs.setStringList(_foldersKey, folders);
    }
  }

  Future<void> removeFolder(String folderName) async {
    if (folderName == _defaultFolder) return;
    final prefs = await _prefs;
    final existing = prefs.getStringList(_foldersKey);
    if (existing == null || existing.isEmpty) return;

    final folders = List<String>.of(existing);
    if (folders.remove(folderName)) {
      await prefs.setStringList(_foldersKey, folders);
    }
  }

  Future<List<NoteModel>> getNotes() async {
    final prefs = await _prefs;
    final String? notesJson = prefs.getString(_notesKey);
    if (notesJson == null || notesJson.isEmpty) return <NoteModel>[];

    try {
      final Object? decoded = jsonDecode(notesJson);
      if (decoded is! List<Object?>) return <NoteModel>[];

      final List<NoteModel> notes = <NoteModel>[];
      for (final Object? item in decoded) {
        if (item is Map<String, Object?>) {
          notes.add(NoteModel.fromJson(item));
        }
      }
      return notes;
    } on FormatException {
      return <NoteModel>[];
    }
  }

  Future<void> saveNotes(List<NoteModel> notes) async {
    final prefs = await _prefs;
    final List<Map<String, Object?>> serialized = <Map<String, Object?>>[
      for (final note in notes) note.toJson(),
    ];
    await prefs.setString(_notesKey, jsonEncode(serialized));
  }
}
