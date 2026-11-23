import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/note_model.dart';

class StorageService {
  static const String _notesKey = 'pindaiku_notes_v2';
  static const String _userNameKey = 'pindaiku_user_name';
  static const String _userEmailKey = 'pindaiku_user_email';
  static const String _userPassKey = 'pindaiku_user_pass';
  static const String _isLoggedInKey = 'pindaiku_is_logged_in';

  Future<void> registerUser(String name, String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, name);
    await prefs.setString(_userEmailKey, email);
    await prefs.setString(_userPassKey, password);
    await prefs.setBool(_isLoggedInKey, true);
  }

  Future<String?> loginUser(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString(_userEmailKey);
    final savedPass = prefs.getString(_userPassKey);

    // Wajib daftar terlebih dahulu jika belum ada akun tersimpan
    if (savedEmail == null || savedEmail.isEmpty) {
      return 'Akun belum terdaftar! Silakan tekan Daftar terlebih dahulu.';
    }

    if (savedEmail == email && savedPass == password) {
      await prefs.setBool(_isLoggedInKey, true);
      return null; // Berhasil masuk
    }
    return 'Email atau kata sandi salah!';
  }

  Future getActiveUser() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_isLoggedInKey) ?? false;
    if (!isLoggedIn) return null;

    final name = prefs.getString(_userNameKey) ?? 'Jose';
    final email = prefs.getString(_userEmailKey) ?? '';
    return {'name': name, 'email': email};
  }

  static const String _foldersKey = 'pindaiku_folders_v1';

  Future<void> logoutUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, false);
  }

  Future<List<String>> getFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? folders = prefs.getStringList(_foldersKey);
    if (folders == null || folders.isEmpty) {
      return ['Dokumen'];
    }
    return folders;
  }

  Future<void> saveFolder(String folderName) async {
    final trimmed = folderName.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final folders = await getFolders();
    if (!folders.contains(trimmed)) {
      folders.add(trimmed);
      await prefs.setStringList(_foldersKey, folders);
    }
  }

  Future<List<NoteModel>> getNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final String? notesJson = prefs.getString(_notesKey);
    if (notesJson == null) return [];

    final List<dynamic> decoded = jsonDecode(notesJson);
    return decoded.map((item) => NoteModel.fromJson(item)).toList();
  }

  Future<void> saveNotes(List<NoteModel> notes) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(notes.map((n) => n.toJson()).toList());
    await prefs.setString(_notesKey, encoded);
  }
}
