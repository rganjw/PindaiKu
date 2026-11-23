import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/note_model.dart';
import '../services/storage_service.dart';
import '../utils/web_helper.dart';

class ScanNoteScreen extends StatefulWidget {
  const ScanNoteScreen({super.key});

  @override
  State<ScanNoteScreen> createState() => _ScanNoteScreenState();
}

class _ScanNoteScreenState extends State<ScanNoteScreen> {
  final _titleController = TextEditingController(
    text: 'PindaiKu - Dokumen.pdf',
  );
  final _contentController = TextEditingController();
  final _picker = ImagePicker();

  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  String _selectedCategory = 'Dokumen';
  List<String> _categories = ['Dokumen'];
  String? _imagePath;
  Uint8List? _imageBytes;
  int _rotationTurns = 0;
  bool _autoScan = true;
  bool _flashOn = false;
  bool _isResultStep = false;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final folders = await StorageService().getFolders();
    if (mounted) {
      setState(() {
        _categories = folders.isNotEmpty ? folders : ['Dokumen'];
        if (!_categories.contains(_selectedCategory)) {
          _selectedCategory = _categories.first;
        }
      });
    }
  }

  void _showAddFolderDialog() {
    final folderInputController = TextEditingController();
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
          controller: folderInputController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Nama Folder',
            hintText: 'Contoh: Pekerjaan, Pribadi, dll.',
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
              final newName = folderInputController.text.trim();
              if (newName.isNotEmpty) {
                await StorageService().saveFolder(newName);
                if (mounted) {
                  setState(() {
                    if (!_categories.contains(newName)) {
                      _categories.add(newName);
                    }
                    _selectedCategory = newName;
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
            child: const Text('Simpan Folder'),
          ),
        ],
      ),
    );
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        final backCamera = _cameras!.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras!.first,
        );
        _cameraController = CameraController(
          backCamera,
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _toggleFlash() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final newFlash = !_flashOn;
        await _cameraController!.setFlashMode(
          newFlash ? FlashMode.torch : FlashMode.off,
        );
        setState(() => _flashOn = newFlash);
      } catch (_) {
        setState(() => _flashOn = !_flashOn);
      }
    } else {
      setState(() => _flashOn = !_flashOn);
    }
  }

  Future<void> _takeLivePicture() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final XFile file = await _cameraController!.takePicture();
        final bytes = await file.readAsBytes();
        setState(() {
          _imageBytes = bytes;
          _imagePath = file.path;
          _rotationTurns = 0;
          _isResultStep = true;
          _contentController.clear();
        });

        if (_autoScan) {
          await _runOcr();
        }
        return;
      } catch (e) {
        debugPrint('Error taking picture: $e');
      }
    }
    // Fallback jika kamera live belum siap
    await _captureOrPick(ImageSource.camera);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _captureOrPick(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      String savedPath = picked.path;
      if (kIsWeb) {
        savedPath = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }

      setState(() {
        _imageBytes = bytes;
        _imagePath = savedPath;
        _rotationTurns = 0;
        _isResultStep = true;
        _contentController.clear();
      });

      if (_autoScan) {
        await _runOcr();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal mengambil gambar: $e')));
    }
  }

  Future<void> _runOcr() async {
    if (_imagePath == null) return;
    setState(() => _isScanning = true);

    try {
      String extractedText = '';

      if (!kIsWeb) {
        final inputImage = InputImage.fromFilePath(_imagePath!);
        final textRecognizer = TextRecognizer(
          script: TextRecognitionScript.latin,
        );
        final RecognizedText recognizedText = await textRecognizer.processImage(
          inputImage,
        );
        await textRecognizer.close();
        extractedText = recognizedText.text;
      } else {
        extractedText = await runWebOcr(_imagePath!);
      }

      setState(() {
        _contentController.text = extractedText.isNotEmpty ? extractedText : 'Teks pada gambar kurang jelas terbaca. Pastikan foto terang dan tidak buram.';
        _isScanning = false;
      });

      if (!mounted) return;
      _showOcrEditorDialog();
    } catch (e) {
      setState(() {
        _contentController.text = 'Gagal memproses OCR: $e';
        _isScanning = false;
      });
    }
  }

  Future<void> _shareAsPdf() async {
    try {
      final pdf = pw.Document();
      final docTitle = _titleController.text.trim().isEmpty
          ? 'Catatan_PindaiKu.pdf'
          : _titleController.text.trim();
      final ocrText = _contentController.text.trim().isEmpty
          ? '(Belum ada teks hasil OCR)'
          : _contentController.text.trim();

      pw.MemoryImage? pdfImage;
      if (_imageBytes != null) {
        pdfImage = pw.MemoryImage(_imageBytes!);
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) => [
            pw.Header(
              level: 0,
              child: pw.Text(
                docTitle,
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Text(
              'Folder: $_selectedCategory',
              style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 16),
            if (pdfImage != null) ...[
              pw.Center(
                child: pw.Container(
                  height: 280,
                  child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
                ),
              ),
              pw.SizedBox(height: 16),
            ],
            pw.Text(
              'Hasil Konversi Teks (OCR):',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text(ocrText, style: const pw.TextStyle(fontSize: 12)),
          ],
        ),
      );

      final pdfBytes = await pdf.save();
      final fileName = docTitle.toLowerCase().endsWith('.pdf')
          ? docTitle
          : '$docTitle.pdf';

      await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal membuat PDF: $e')));
    }
  }

  Future<void> _exportAsJpeg() async {
    if (_imageBytes == null || _imagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada gambar untuk diekspor!')),
      );
      return;
    }

    try {
      final baseName = _titleController.text
          .trim()
          .replaceAll('.pdf', '')
          .replaceAll(' ', '_');
      final fileName = '${baseName.isEmpty ? 'PindaiKu' : baseName}.jpg';

      if (kIsWeb) {
        downloadWebImage(_imagePath!, fileName);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File $fileName berhasil diunduh!')),
        );
      } else {
        final dir = Directory.systemTemp;
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(_imageBytes!);

        // Coba simpan salinan langsung ke folder publik Download di Android
        String savedMsg = '';
        try {
          final publicDownloadDir = Directory('/storage/emulated/0/Download');
          if (await publicDownloadDir.exists()) {
            final publicFile = File('${publicDownloadDir.path}/$fileName');
            await publicFile.writeAsBytes(_imageBytes!);
            savedMsg = ' & tersimpan di folder Download';
          }
        } catch (_) {}

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File $fileName siap dibagikan$savedMsg!')),
        );

        // Buka Android share sheet agar user bisa simpan ke Galeri / WA / Drive dll
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'image/jpeg', name: fileName)],
            text: 'Catatan JPEG PindaiKu: $fileName',
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal ekspor JPEG: $e')));
    }
  }

  void _showOcrEditorDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Edit Teks Catatan (Hasil OCR)',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded),
                  tooltip: 'Salin Teks',
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: _contentController.text),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Teks disalin!')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _contentController,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: 'Tulis atau rapikan teks catatan di sini...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1967D2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text('Selesai & Gunakan Teks Ini'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveDocument() async {
    final title = _titleController.text.trim().isEmpty
        ? 'Pemindaian Baru'
        : _titleController.text.trim();
    final content = _contentController.text.trim().isEmpty
        ? 'Catatan hasil pemindaian dokumen.'
        : _contentController.text.trim();

    await StorageService().saveFolder(_selectedCategory);

    final note = NoteModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      subject: 'Umum',
      category: _selectedCategory,
      content: content,
      createdAt: DateTime.now(),
      imagePath: _imagePath,
    );

    if (!mounted) return;
    Navigator.pop(context, note);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isResultStep) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 76,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B2B2B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF29B6F6).withOpacity(0.6),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_isCameraInitialized && _cameraController != null)
                          SizedBox.expand(
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _cameraController!.value.previewSize?.height ?? 1,
                                height: _cameraController!.value.previewSize?.width ?? 1,
                                child: CameraPreview(_cameraController!),
                              ),
                            ),
                          )
                        else
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.document_scanner_outlined,
                                size: 64,
                                color: Colors.white.withOpacity(0.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Arahkan ke teks atau dokumen\nlalu tekan tombol rana di bawah',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.75),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        Container(
                          height: 3,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF29B6F6),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF29B6F6).withOpacity(0.8),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    IconButton(
                      icon: Icon(
                        _flashOn ? Icons.flash_on : Icons.flash_off,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: _toggleFlash,
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 24,
                left: 28,
                right: 28,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => _captureOrPick(ImageSource.gallery),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.photo_library_outlined,
                            color: Colors.white,
                            size: 28,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Gallery',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _takeLivePicture,
                      child: Container(
                        width: 72,
                        height: 72,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3.5),
                        ),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: _autoScan,
                          activeColor: const Color(0xFF00ACC1),
                          onChanged: (val) => setState(() => _autoScan = val),
                        ),
                        const Text(
                          'Auto-Scan',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => setState(() => _isResultStep = false),
        ),
        actions: [
          // Tombol Putar Foto 90 Derajat (Fungsi Unik 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _rotationTurns = (_rotationTurns + 1) % 4;
                });
              },
              icon: const Icon(Icons.rotate_right, size: 16),
              label: const Text('Putar', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade200,
                foregroundColor: Colors.black87,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          // Menu Titik Tiga: Edit Teks Manual / Salin Teks / Foto Ulang (Fungsi Unik 2)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: Colors.black87),
            onSelected: (value) {
              if (value == 'edit_text') {
                _showOcrEditorDialog();
              } else if (value == 'copy_text') {
                Clipboard.setData(ClipboardData(text: _contentController.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Teks catatan disalin!')),
                );
              } else if (value == 'retake') {
                setState(() => _isResultStep = false);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit_text',
                child: Row(
                  children: [
                    Icon(Icons.edit_note, size: 20),
                    SizedBox(width: 8),
                    Text('Edit Teks Manual'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'copy_text',
                child: Row(
                  children: [
                    Icon(Icons.copy_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Salin Hasil Teks'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'retake',
                child: Row(
                  children: [
                    Icon(Icons.camera_alt_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Ambil Ulang Foto'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              height: 270,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFD9D9D9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: RotatedBox(
                  quarterTurns: _rotationTurns,
                  child: Container(
                    width: 190,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: _imageBytes != null
                        ? Image.memory(_imageBytes!, fit: BoxFit.contain)
                        : (_imagePath != null && !kIsWeb
                              ? Image.file(
                                  File(_imagePath!),
                                  fit: BoxFit.contain,
                                )
                              : const Center(
                                  child: Icon(Icons.description, size: 48),
                                )),
                  ),
                ),
              ),
            ),
            if (_isScanning) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(color: Color(0xFF00ACC1)),
              const SizedBox(height: 6),
              const Text(
                'Sedang membaca teks dari foto secara otomatis...',
                style: TextStyle(fontSize: 12, color: Color(0xFF00ACC1)),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Nama Dokumen',
                suffixIcon: const Icon(Icons.edit_outlined, size: 20),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
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
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _categories.contains(_selectedCategory) ? _selectedCategory : null,
              decoration: InputDecoration(
                labelText: 'Folder Dokumen',
                prefixIcon: const Icon(
                  Icons.folder_outlined,
                  color: Color(0xFF00ACC1),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined, color: Color(0xFF00ACC1)),
                  tooltip: 'Buat Folder Baru',
                  onPressed: _showAddFolderDialog,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              items: [
                ..._categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                const DropdownMenuItem(
                  value: '__new_folder__',
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline, color: Color(0xFF1967D2), size: 18),
                      SizedBox(width: 8),
                      Text(
                        '+ Buat Folder Baru...',
                        style: TextStyle(
                          color: Color(0xFF1967D2),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              onChanged: (val) {
                if (val == '__new_folder__') {
                  _showAddFolderDialog();
                } else if (val != null) {
                  setState(() => _selectedCategory = val);
                }
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _shareAsPdf,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1967D2),
                      side: const BorderSide(color: Color(0xFF1967D2)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      'Bagikan (PDF)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _exportAsJpeg,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1967D2),
                      side: const BorderSide(color: Color(0xFF1967D2)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      'Ekspor (JPEG)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isScanning ? null : _runOcr,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1967D2),
                  side: const BorderSide(color: Color(0xFF1967D2)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: Text(
                  _isScanning ? 'Membaca Teks...' : 'Konversi ke Teks (OCR)',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saveDocument,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1967D2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Simpan & Lihat Dokumen',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
