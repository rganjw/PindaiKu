import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/note_model.dart';
import '../services/storage_service.dart';
import 'login_screen.dart';
import 'scan_note_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storage = StorageService();
  final _searchController = TextEditingController();
  List<NoteModel> _notes = [];
  List<String> _folders = ['Dokumen'];
  final List<String> _notifications = [
    'Selamat datang di PindaiKu! Siap memindai dokumen Anda.',
  ];
  String _userName = 'Jose';
  String _userEmail = '';
  String _searchQuery = '';
  String _selectedFolder = 'Semua';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = await _storage.getActiveUser();
    final notes = await _storage.getNotes();
    final savedFolders = await _storage.getFolders();
    final Set<String> folderSet = {'Dokumen', ...savedFolders};
    for (var n in notes) {
      if (n.category.trim().isNotEmpty) {
        folderSet.add(n.category.trim());
      }
    }
    if (mounted) {
      setState(() {
        if (user != null) {
          _userName = user['name']!;
          _userEmail = user['email']!;
        }
        _notes = notes;
        _folders = folderSet.toList();
      });
    }
  }

  void _showCreateFolderDialog() {
    final folderController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.create_new_folder_outlined, color: Color(0xFF00ACC1)),
            SizedBox(width: 8),
            Text('Buat Folder Baru', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: TextField(
          controller: folderController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Nama Folder',
            hintText: 'Contoh: Arsip, Keuangan, Pribadi',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = folderController.text.trim();
              if (name.isNotEmpty) {
                await _storage.saveFolder(name);
                if (mounted) {
                  setState(() {
                    if (!_folders.contains(name)) {
                      _folders.add(name);
                    }
                  });
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1967D2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _openScanner() async {
    final NoteModel? result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScanNoteScreen()),
    );

    if (result != null) {
      setState(() {
        _notes.insert(0, result);
        if (!_folders.contains(result.category)) {
          _folders.add(result.category);
        }
        _notifications.insert(
          0,
          'Berhasil menyimpan "${result.title}" ke folder ${result.category}',
        );
      });
      await _storage.saveNotes(_notes);
    }
  }

  Future<void> _confirmDeleteNote(
    NoteModel note, {
    bool fromModal = false,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Hapus Dokumen?'),
        content: Text('Yakin ingin menghapus "${note.title}" secara permanen?'),
        actions: [
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
        _notes.removeWhere((item) => item.id == note.id);
        _notifications.insert(0, 'Menghapus dokumen "${note.title}"');
      });
      await _storage.saveNotes(_notes);
      if (fromModal && mounted) {
        Navigator.pop(context);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${note.title}" berhasil dihapus')),
      );
    }
  }

  void _showNotificationsDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Notifikasi & Aktivitas',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _notifications.clear());
                    Navigator.pop(ctx);
                  },
                  child: const Text('Bersihkan'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('Tidak ada notifikasi baru.')),
              )
            else
              ..._notifications
                  .take(5)
                  .map(
                    (notif) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE0F7FA),
                        child: Icon(
                          Icons.notifications_active,
                          color: Color(0xFF00ACC1),
                          size: 20,
                        ),
                      ),
                      title: Text(notif, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  void _showSettingsDialog() {
    final nameEditController = TextEditingController(text: _userName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.settings, color: Color(0xFF1967D2)),
            SizedBox(width: 8),
            Text('Pengaturan Akun'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ubah Nama Tampilan',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: nameEditController,
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
                  setState(() => _notes.clear());
                  await _storage.saveNotes([]);
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Semua catatan berhasil dihapus.'),
                    ),
                  );
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameEditController.text.trim();
              if (newName.isNotEmpty) {
                await _storage.registerUser(newName, _userEmail, '123456');
                setState(() => _userName = newName);
              }
              if (!mounted) return;
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1967D2),
              foregroundColor: Colors.white,
            ),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Konfirmasi Keluar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Apakah Anda yakin ingin keluar dari akun PindaiKu?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
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
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Color(0xFF00ACC1)),
            SizedBox(width: 8),
            Text('Panduan PindaiKu'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1967D2),
              foregroundColor: Colors.white,
            ),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
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
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  void _showNoteDetail(NoteModel note) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            controller: controller,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        label: Text(note.category),
                        backgroundColor: const Color(0xFF1967D2)
                            .withOpacity(0.12),
                      ),
                      Chip(
                        label: Text(note.subject),
                        backgroundColor: const Color(0xFF00ACC1)
                            .withOpacity(0.15),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy_rounded),
                        tooltip: 'Salin Teks',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: note.content));
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Teks catatan disalin!'),
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
                _formatDate(note.createdAt),
                style: const TextStyle(fontSize: 12, color: Color(0xFF00ACC1)),
              ),
              const SizedBox(height: 16),
              if (note.imagePath != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: kIsWeb
                      ? Image.network(
                          note.imagePath!,
                          height: 180,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        )
                      : Image.file(
                          File(note.imagePath!),
                          height: 180,
                          fit: BoxFit.cover,
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
      ),
    );
  }

  Widget _buildFolderCard(String label) {
    final isSelected = _selectedFolder == label;
    final count = _notes.where((n) => n.category == label).length;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFolder = isSelected ? 'Semua' : label;
        });
      },
      child: Column(
        children: [
          Container(
            height: 84,
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF00ACC1).withOpacity(0.18)
                  : const Color(0xFFE0E0E0),
              borderRadius: BorderRadius.circular(14),
              border: isSelected
                  ? Border.all(color: const Color(0xFF00ACC1), width: 2)
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.folder_outlined,
                  size: 44,
                  color: Color(0xFF00ACC1),
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
                        color: const Color(0xFF1967D2),
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
              color: isSelected ? const Color(0xFF00ACC1) : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredNotes = _notes.where((n) {
      final matchSearch =
          n.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          n.subject.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          n.content.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchFolder =
          _selectedFolder == 'Semua' || n.category == _selectedFolder;
      return matchSearch && matchFolder;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
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
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 42,
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
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
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
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
                    color: const Color(0xFF00ACC1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                          border: Border.all(color: Colors.white, width: 3.5),
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
                children: [
                  Row(
                    children: [
                      const Text(
                        'Folder Dokumen',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _showCreateFolderDialog,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00ACC1).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 14, color: Color(0xFF00ACC1)),
                              SizedBox(width: 2),
                              Text(
                                'Folder Baru',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF00ACC1),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedFolder != 'Semua')
                    GestureDetector(
                      onTap: () => setState(() => _selectedFolder = 'Semua'),
                      child: const Text(
                        'Tampilkan Semua',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1967D2),
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
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final f = _folders[index];
                    return SizedBox(
                      width: 105,
                      child: _buildFolderCard(f),
                    );
                  },
                ),
              ),
              const SizedBox(height: 22),
              Text(
                _selectedFolder == 'Semua'
                    ? 'Pemindaian Terbaru'
                    : 'Folder: $_selectedFolder (${filteredNotes.length})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              if (filteredNotes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      _selectedFolder == 'Semua'
                          ? 'Belum ada pemindaian. Tekan tombol scan di bawah!'
                          : 'Belum ada dokumen di folder "$_selectedFolder".',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredNotes.length,
                  itemBuilder: (context, index) {
                    final note = filteredNotes[index];
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
                          color: Color(0xFF00ACC1),
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
                        '${_formatDate(note.createdAt)} • ${note.category}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF00ACC1),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                  },
                ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: GestureDetector(
        onTap: _openScanner,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFE0E0E0),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.document_scanner_outlined,
            color: Colors.black87,
            size: 28,
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: const Color(0xFF1967D2),
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: const Icon(Icons.home_outlined, color: Colors.black87),
              tooltip: 'Beranda',
              onPressed: () => setState(() {
                _selectedFolder = 'Semua';
                _searchController.clear();
                _searchQuery = '';
              }),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.black87),
              tooltip: 'Pengaturan',
              onPressed: _showSettingsDialog,
            ),
            const SizedBox(width: 48),
            IconButton(
              icon: const Icon(Icons.help_outline, color: Colors.black87),
              tooltip: 'Bantuan',
              onPressed: _showHelpDialog,
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.black87),
              tooltip: 'Keluar Akun',
              onPressed: _confirmLogout,
            ),
          ],
        ),
      ),
    );
  }
}
