import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/note_model.dart';
import '../services/storage_service.dart';
import '../utils/app_constants.dart';
import '../widgets/shared_widgets.dart';
import 'login_screen.dart';
import 'scan_note_screen.dart';

typedef _NotificationEntry = ({int id, String message});

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final StorageService _storage = StorageService();
  final TextEditingController _searchController = TextEditingController();

  List<NoteModel> _notes = <NoteModel>[];
  List<NoteModel> _filteredNotes = <NoteModel>[];
  Map<String, int> _folderCounts = <String, int>{};
  List<String> _folders = <String>[AppConstants.defaultFolder];

  int _nextNotificationId = 2;
  final List<_NotificationEntry> _notifications = <_NotificationEntry>[
    (
      id: 1,
      message: 'Selamat datang di PindaiKu! Siap memindai dokumen Anda.',
    ),
  ];

  String _userName = 'Jose';
  String _searchQuery = '';
  String _selectedFolder = AppConstants.allFolders;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _addNotification(String message) {
    _notifications.insert(
      0,
      (id: _nextNotificationId++, message: message),
    );
  }

  void _rebuildFolderCounts() {
    final Map<String, int> counts = <String, int>{};
    for (final NoteModel note in _notes) {
      counts[note.category] = (counts[note.category] ?? 0) + 1;
    }
    _folderCounts = counts;
  }

  void _rebuildFilteredNotes() {
    final String query = _searchQuery.trim().toLowerCase();
    final bool hasQuery = query.isNotEmpty;
    final bool filterByFolder = _selectedFolder != AppConstants.allFolders;

    if (!hasQuery && !filterByFolder) {
      _filteredNotes = List<NoteModel>.of(_notes);
      return;
    }

    final List<NoteModel> result = <NoteModel>[];
    for (final NoteModel note in _notes) {
      if (filterByFolder && note.category != _selectedFolder) {
        continue;
      }
      if (hasQuery && !note.searchIndex.contains(query)) {
        continue;
      }
      result.add(note);
    }
    _filteredNotes = result;
  }

  Future<void> _loadData() async {
    final (
      ActiveUser? user,
      List<NoteModel> notes,
      List<String> savedFolders,
    ) = await (
      _storage.getActiveUser(),
      _storage.getNotes(),
      _storage.getFolders(),
    ).wait;

    final Set<String> folderSet = <String>{
      AppConstants.defaultFolder,
      ...savedFolders,
    };
    for (final NoteModel n in notes) {
      final String trimmedCategory = n.category.trim();
      if (trimmedCategory.isNotEmpty) {
        folderSet.add(trimmedCategory);
      }
    }

    if (mounted) {
      setState(() {
        if (user != null) {
          _userName = user.name;
        }
        _notes = notes;
        _folders = folderSet.toList();
        _rebuildFolderCounts();
        _rebuildFilteredNotes();
      });
    }
  }

  Future<void> _showCreateFolderModal() async {
    final String? name = await showCreateFolderDialog(
      context,
      hintText: 'Contoh: Arsip, Keuangan, Pribadi',
      confirmLabel: 'Simpan',
    );
    if (name == null || name.isEmpty) return;

    await _storage.saveFolder(name);
    if (!mounted) return;
    setState(() {
      if (!_folders.contains(name)) {
        _folders.add(name);
      }
    });
  }

  Future<void> _openScanner() async {
    final NoteModel? result = await Navigator.push<NoteModel>(
      context,
      MaterialPageRoute<NoteModel>(builder: (_) => const ScanNoteScreen()),
    );

    // Muat ulang daftar folder jika user sempat membuat folder baru di ScanNoteScreen
    final List<String> latestFolders = await _storage.getFolders();

    if (!mounted) return;
    if (result != null) {
      setState(() {
        _notes.insert(0, result);
        for (final String f in latestFolders) {
          if (!_folders.contains(f)) {
            _folders.add(f);
          }
        }
        if (!_folders.contains(result.category)) {
          _folders.add(result.category);
        }
        _addNotification(
          'Berhasil menyimpan "${result.title}" ke folder ${result.category}',
        );
        _rebuildFolderCounts();
        _rebuildFilteredNotes();
      });
      await _storage.saveNotes(_notes);
    } else {
      setState(() {
        for (final String f in latestFolders) {
          if (!_folders.contains(f)) {
            _folders.add(f);
          }
        }
      });
    }
  }

  Future<void> _confirmDeleteNote(
    NoteModel note, {
    bool fromModal = false,
  }) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Hapus Dokumen?'),
        content: Text('Yakin ingin menghapus "${note.title}" secara permanen?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _notes.removeWhere((NoteModel item) => item.id == note.id);
        _addNotification('Menghapus dokumen "${note.title}"');
        _rebuildFolderCounts();
        _rebuildFilteredNotes();
      });
      await _storage.saveNotes(_notes);
      if (fromModal && mounted) {
        Navigator.pop(context);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${note.title}" berhasil dihapus'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmDeleteFolder(String label) async {
    if (label == AppConstants.defaultFolder) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Hapus Folder?'),
        content: Text(
          'Yakin ingin menghapus folder "$label"? Semua dokumen di dalamnya akan dipindahkan ke folder "Dokumen".',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storage.removeFolder(label);
      setState(() {
        _folders.remove(label);
        if (_selectedFolder == label) {
          _selectedFolder = AppConstants.allFolders;
        }
        for (int i = 0; i < _notes.length; i++) {
          if (_notes[i].category == label) {
            _notes[i] = _notes[i].copyWith(
              category: AppConstants.defaultFolder,
            );
          }
        }
        _rebuildFolderCounts();
        _rebuildFilteredNotes();
      });
      await _storage.saveNotes(_notes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Folder "$label" dihapus.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showNotificationsDialog() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Tutup',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (
        BuildContext dialogContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        return StatefulBuilder(
          builder: (BuildContext panelContext, StateSetter setDialogState) {
            final int visibleCount = _notifications.length > 10
                ? 10
                : _notifications.length;

            return Align(
              alignment: Alignment.centerRight,
              child: Material(
                elevation: 16,
                child: Container(
                  width: MediaQuery.sizeOf(panelContext).width * 0.85,
                  height: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.only(
                    top: 50,
                    left: 24,
                    right: 24,
                    bottom: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          IconButton(
                            icon: const Icon(Icons.chevron_right, size: 28),
                            onPressed: () => Navigator.pop(dialogContext),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Notifikasi',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(_notifications.clear);
                              Navigator.pop(dialogContext);
                            },
                            icon: const Icon(
                              Icons.delete_sweep_outlined,
                              size: 20,
                              color: Colors.redAccent,
                            ),
                            label: const Text(
                              'Bersihkan',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 13,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      Expanded(
                        child: visibleCount == 0
                            ? const Center(
                                child: Text('Tidak ada notifikasi baru.'),
                              )
                            : ListView.builder(
                                itemCount: visibleCount,
                                itemBuilder: (BuildContext context, int index) {
                                  final _NotificationEntry notif =
                                      _notifications[index];
                                  return Dismissible(
                                    key: ValueKey<int>(notif.id),
                                    direction: DismissDirection.startToEnd,
                                    background: Container(
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.only(left: 20),
                                      color: Colors.red,
                                      child: const Icon(
                                        Icons.delete,
                                        color: Colors.white,
                                      ),
                                    ),
                                    onDismissed: (_) {
                                      setState(() {
                                        _notifications.removeWhere(
                                          (_NotificationEntry item) =>
                                              item.id == notif.id,
                                        );
                                      });
                                      setDialogState(() {});
                                    },
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                      leading: const CircleAvatar(
                                        backgroundColor:
                                            AppConstants.notifAvatarBg,
                                        child: Icon(
                                          Icons.notifications_active_outlined,
                                          color: AppConstants.accentCyan,
                                        ),
                                      ),
                                      title: Text(
                                        notif.message,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
    );
  }

  Future<void> _showSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AccountSettingsDialog(
        initialName: _userName,
        onSaveName: (String newName) async {
          await _storage.updateUserName(newName);
          if (!mounted) return;
          setState(() => _userName = newName);
        },
        onClearAllNotes: () async {
          setState(() {
            _notes.clear();
            _rebuildFolderCounts();
            _rebuildFilteredNotes();
          });
          await _storage.saveNotes(const <NoteModel>[]);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Semua catatan berhasil dihapus.'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }

  void _confirmLogout() {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: <Widget>[
            Icon(Icons.logout_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text(
              'Konfirmasi Keluar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'Apakah Anda yakin ingin keluar dari akun PindaiKu?',
          style: TextStyle(fontSize: 14),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Batal',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _storage.logoutUser();
              if (!mounted) return;
              await Navigator.pushReplacement(
                context,
                MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: <Widget>[
            Icon(Icons.help_outline, color: AppConstants.accentCyan),
            SizedBox(width: 8),
            Text('Panduan PindaiKu'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '1. Tekan kartu "Mulai Pindai Cepat" atau ikon scan di tengah bawah.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 8),
            Text(
              '2. Ambil foto teks via kamera atau pilih gambar dari galeri.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 8),
            Text(
              '3. Pilih Folder Dokumen lalu tekan "Simpan & Lihat Dokumen".',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 8),
            Text(
              '4. Klik folder di beranda untuk memfilter catatan, atau tekan ikon sampah untuk menghapus.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: <Widget>[
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  void _showNoteDetail(NoteModel note) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext sheetContext) {
        final int targetCacheHeight =
            (180 * MediaQuery.devicePixelRatioOf(sheetContext)).round();

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.92,
          builder: (_, ScrollController controller) => Padding(
            padding: const EdgeInsets.all(24),
            child: ListView(
              controller: controller,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Wrap(
                      spacing: 8,
                      children: <Widget>[
                        Chip(
                          label: Text(note.category),
                          backgroundColor: AppConstants.primaryBlue.withValues(
                            alpha: 0.12,
                          ),
                        ),
                        Chip(
                          label: Text(note.subject),
                          backgroundColor: AppConstants.accentCyan.withValues(
                            alpha: 0.15,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        IconButton(
                          icon: const Icon(Icons.copy_rounded),
                          tooltip: 'Salin Teks',
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: note.content),
                            );
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Teks catatan disalin!'),
                                backgroundColor: Colors.teal,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          tooltip: 'Hapus Dokumen',
                          onPressed: () =>
                              _confirmDeleteNote(note, fromModal: true),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  note.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  AppConstants.formatIndonesianDate(note.createdAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppConstants.accentCyan,
                  ),
                ),
                const SizedBox(height: 16),
                if (note.imagePath != null) ...<Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: kIsWeb
                        ? Image.network(
                            note.imagePath!,
                            height: 180,
                            cacheHeight: targetCacheHeight,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          )
                        : Image.file(
                            File(note.imagePath!),
                            height: 180,
                            cacheHeight: targetCacheHeight,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text(
                  'Hasil Konversi Teks (OCR):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    note.content,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFolderCard(String label) {
    final bool isSelected = _selectedFolder == label;
    final int count = _folderCounts[label] ?? 0;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFolder = isSelected ? AppConstants.allFolders : label;
          _rebuildFilteredNotes();
        });
      },
      onLongPress: label == AppConstants.defaultFolder
          ? null
          : () => _confirmDeleteFolder(label),
      child: Column(
        children: <Widget>[
          Container(
            height: 75,
            width: 85,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppConstants.accentCyan.withValues(alpha: 0.18)
                  : AppConstants.folderIdleBg,
              borderRadius: BorderRadius.circular(14),
              border: isSelected
                  ? Border.all(color: AppConstants.accentCyan, width: 2)
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                const Icon(
                  Icons.folder_outlined,
                  size: 44,
                  color: AppConstants.accentCyan,
                ),
                if (count > 0)
                  Positioned(
                    top: 8,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryBlue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? AppConstants.accentCyan : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteTile(NoteModel note) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 2),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.description_outlined,
          color: AppConstants.accentCyan,
        ),
      ),
      title: Text(
        note.title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '${AppConstants.formatIndonesianDate(note.createdAt)} • ${note.category}',
        style: const TextStyle(
          fontSize: 12,
          color: AppConstants.accentCyan,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              color: Colors.redAccent,
              size: 20,
            ),
            tooltip: 'Hapus',
            onPressed: () => _confirmDeleteNote(note),
          ),
          const Icon(
            Icons.chevron_right,
            color: Colors.black54,
          ),
        ],
      ),
      onTap: () => _showNoteDetail(note),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: <Widget>[
          SafeArea(
            child: CustomScrollView(
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            GestureDetector(
                              onTap: _showSettingsDialog,
                              child: const Icon(
                                Icons.person_outline,
                                size: 28,
                                color: Colors.black87,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.notifications_none,
                                size: 28,
                                color: Colors.black87,
                              ),
                              onPressed: _showNotificationsDialog,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Halo, $_userName!',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.textDark,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 42,
                          child: TextField(
                            controller: _searchController,
                            onChanged: (String val) {
                              setState(() {
                                _searchQuery = val;
                                _rebuildFilteredNotes();
                              });
                            },
                            decoration: InputDecoration(
                              hintText: 'Cari catatan atau dokumen...',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade400,
                              ),
                              prefixIcon: const Icon(
                                Icons.search,
                                size: 20,
                                color: Colors.black54,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 0,
                              ),
                              border: AppConstants.inputBorder,
                              enabledBorder: AppConstants.inputBorder,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        GestureDetector(
                          onTap: _openScanner,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppConstants.accentCyan,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: <Widget>[
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        'Mulai Pindai Cepat',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 19,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        'Foto teks dan ubah\nmenjadi teks digital',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3.5,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.note_add_outlined,
                                    color: Colors.white,
                                    size: 46,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                const Text(
                                  'Folder',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                if (_selectedFolder !=
                                        AppConstants.allFolders &&
                                    _selectedFolder !=
                                        AppConstants.defaultFolder)
                                  GestureDetector(
                                    onTap: () =>
                                        _confirmDeleteFolder(_selectedFolder),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Icon(
                                            Icons.delete_outline,
                                            size: 14,
                                            color: Colors.redAccent,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Hapus Folder',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.redAccent,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (_selectedFolder != AppConstants.allFolders)
                              GestureDetector(
                                onTap: () => setState(() {
                                  _selectedFolder = AppConstants.allFolders;
                                  _rebuildFilteredNotes();
                                }),
                                child: const Text(
                                  'Tampilkan Semua',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppConstants.primaryBlue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 114,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _folders.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 12),
                            itemBuilder: (BuildContext context, int index) {
                              final String f = _folders[index];
                              return SizedBox(
                                width: 105,
                                child: _buildFolderCard(f),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          _selectedFolder == AppConstants.allFolders
                              ? 'Pemindaian Terbaru'
                              : 'Folder: $_selectedFolder (${_filteredNotes.length})',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
                if (_filteredNotes.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 110),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: Text(
                          _selectedFolder == AppConstants.allFolders
                              ? 'Belum ada pemindaian. Tekan tombol scan di bawah!'
                              : 'Belum ada dokumen di folder "$_selectedFolder".',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 90),
                    sliver: SliverList.builder(
                      itemCount: _filteredNotes.length,
                      itemBuilder: (BuildContext context, int index) {
                        return _buildNoteTile(_filteredNotes[index]);
                      },
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            bottom: 24,
            right: 24,
            child: FloatingActionButton(
              heroTag: 'addFolderFAB',
              onPressed: _showCreateFolderModal,
              backgroundColor: AppConstants.accentCyan,
              elevation: 4,
              child: const Icon(
                Icons.create_new_folder_outlined,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: _openScanner,
          backgroundColor: Colors.white,
          elevation: 0,
          shape: const CircleBorder(),
          child: const Icon(
            Icons.document_scanner_outlined,
            color: AppConstants.accentCyan,
            size: 28,
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: AppConstants.accentCyan,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        height: 65,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.home_outlined, color: Colors.white),
              tooltip: 'Beranda',
              onPressed: () => setState(() {
                _selectedFolder = AppConstants.allFolders;
                _searchController.clear();
                _searchQuery = '';
                _rebuildFilteredNotes();
              }),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              tooltip: 'Pengaturan',
              onPressed: _showSettingsDialog,
            ),
            const SizedBox(width: 48),
            IconButton(
              icon: const Icon(Icons.help_outline, color: Colors.white),
              tooltip: 'Bantuan',
              onPressed: _showHelpDialog,
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.white),
              tooltip: 'Keluar Akun',
              onPressed: _confirmLogout,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountSettingsDialog extends StatefulWidget {
  final String initialName;
  final Future<void> Function(String newName) onSaveName;
  final Future<void> Function() onClearAllNotes;

  const _AccountSettingsDialog({
    required this.initialName,
    required this.onSaveName,
    required this.onClearAllNotes,
  });

  @override
  State<_AccountSettingsDialog> createState() => _AccountSettingsDialogState();
}

class _AccountSettingsDialogState extends State<_AccountSettingsDialog> {
  late final TextEditingController _nameEditController;

  @override
  void initState() {
    super.initState();
    _nameEditController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameEditController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: <Widget>[
          Icon(Icons.settings, color: AppConstants.primaryBlue),
          SizedBox(width: 8),
          Text('Pengaturan Akun'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Ubah Nama Tampilan',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _nameEditController,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final bool? confirm = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext ctxConfirm) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    title: const Text('Hapus Semua Catatan?'),
                    content: const Text(
                      'Yakin ingin menghapus semua catatan secara permanen? Aksi ini tidak dapat dibatalkan.',
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(ctxConfirm, false),
                        child: const Text('Batal'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctxConfirm, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Hapus Semua'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await widget.onClearAllNotes();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text(
                'Hapus Semua Catatan',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () async {
            final String newName = _nameEditController.text.trim();
            if (newName.isNotEmpty) {
              await widget.onSaveName(newName);
            }
            if (!context.mounted) return;
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConstants.primaryBlue,
            foregroundColor: Colors.white,
          ),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
