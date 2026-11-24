import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/note_model.dart';
import '../services/scan_export_service.dart';
import '../services/storage_service.dart';
import '../utils/app_constants.dart';
import '../widgets/shared_widgets.dart';

class ScanNoteScreen extends StatefulWidget {
  const ScanNoteScreen({super.key});

  @override
  State<ScanNoteScreen> createState() => _ScanNoteScreenState();
}

class _ScanNoteScreenState extends State<ScanNoteScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _titleController = TextEditingController(
    text: 'PindaiKu - Dokumen.pdf',
  );
  final TextEditingController _contentController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final StorageService _storage = StorageService();
  final ScanExportService _exportService = const ScanExportService();

  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  Future<void> _cameraOpQueue = Future<void>.value();
  int _scanSessionId = 0;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  bool _isExternalPickerActive = false;

  late final AnimationController _scanAnimationController;
  late final Animation<double> _scanAnimation;

  String _selectedCategory = AppConstants.defaultFolder;
  int _dropdownResetNonce = 0;
  List<String> _categories = <String>[AppConstants.defaultFolder];
  String? _imagePath;
  Uint8List? _imageBytes;
  int _rotationTurns = 0;
  bool _autoScan = true;
  bool _flashOn = false;
  bool _isResultStep = false;
  bool _isScanning = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _loadFolders();

    _scanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: -0.9, end: 0.9).animate(
      CurvedAnimation(
        parent: _scanAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanAnimationController.dispose();
    final CameraController? controller = _cameraController;
    _cameraController = null;
    controller?.dispose();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _enqueueCameraOp(Future<void> Function() action) {
    final Future<void> next = _cameraOpQueue.then((_) => action()).catchError((
      Object e,
    ) {
      debugPrint('Camera operation error: $e');
    });
    _cameraOpQueue = next;
    return next;
  }

  Future<void> _releaseCamera() {
    return _enqueueCameraOp(() async {
      final CameraController? controller = _cameraController;
      if (controller == null) return;

      final bool wasFlashOn = _flashOn;
      _cameraController = null;

      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _flashOn = false;
        });
        final AppLifecycleState? lifecycle =
            WidgetsBinding.instance.lifecycleState;
        if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
          // Pastikan widget CameraPreview sudah terlepas dari tree pada frame ini
          // sebelum controller.dispose(), dengan batas 100ms bila VSync berhenti.
          await WidgetsBinding.instance.endOfFrame.timeout(
            const Duration(milliseconds: 100),
            onTimeout: () {},
          );
        }
      }

      if (wasFlashOn && controller.value.isInitialized) {
        try {
          await controller.setFlashMode(FlashMode.off);
        } on Exception catch (_) {}
      }

      try {
        await controller.dispose();
      } on Exception catch (e) {
        debugPrint('Error disposing camera: $e');
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isExternalPickerActive) return;

    if (state == AppLifecycleState.inactive) {
      _scanAnimationController.stop();
      _releaseCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (!_isResultStep) {
        if (!_scanAnimationController.isAnimating) {
          _scanAnimationController.repeat(reverse: true);
        }
        _initCamera();
      }
    }
  }

  Future<void> _enterResultStep({
    required Uint8List bytes,
    required String path,
  }) async {
    _scanSessionId++;
    _scanAnimationController.stop();

    if (!mounted) return;
    setState(() {
      _imageBytes = bytes;
      _imagePath = path;
      _rotationTurns = 0;
      _isScanning = false;
      _isResultStep = true;
      _contentController.clear();
    });

    await _releaseCamera();
  }

  Future<void> _returnToCameraStep() async {
    _scanSessionId++;
    setState(() {
      _isScanning = false;
      _isResultStep = false;
    });
    if (!_scanAnimationController.isAnimating) {
      _scanAnimationController.repeat(reverse: true);
    }
    await _initCamera();
  }

  Future<void> _loadFolders() async {
    final List<String> folders = await _storage.getFolders();
    if (mounted) {
      setState(() {
        _categories = folders.isNotEmpty
            ? folders
            : <String>[AppConstants.defaultFolder];
        if (!_categories.contains(_selectedCategory)) {
          _selectedCategory = _categories.first;
        }
      });
    }
  }

  Future<void> _showAddFolderDialog() async {
    final String? newName = await showCreateFolderDialog(
      context,
      hintText: 'Contoh: Pekerjaan, Pribadi, dll.',
      confirmLabel: 'Simpan Folder',
    );
    if (newName == null || newName.isEmpty) return;

    await _storage.saveFolder(newName);
    if (!mounted) return;
    setState(() {
      if (!_categories.contains(newName)) {
        _categories.add(newName);
      }
      _selectedCategory = newName;
    });
  }

  Future<void> _initCamera() {
    return _enqueueCameraOp(() async {
      if (!mounted || _isResultStep) return;
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        return;
      }

      try {
        _cameras ??= await availableCameras();
        final List<CameraDescription>? cameras = _cameras;
        if (cameras == null || cameras.isEmpty) return;

        final CameraDescription backCamera = cameras.firstWhere(
          (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        );

        CameraController? initializedController;
        for (int attempt = 0; attempt < 2; attempt++) {
          final CameraController candidate = CameraController(
            backCamera,
            ResolutionPreset.high,
            enableAudio: false,
          );
          try {
            await candidate.initialize();
            initializedController = candidate;
            break;
          } on Exception catch (e) {
            await candidate.dispose();
            if (attempt == 0) {
              // Beri jeda singkat jika HAL kamera OS masih melepas sesi sebelumnya
              await Future<void>.delayed(const Duration(milliseconds: 200));
            } else {
              debugPrint('Error initializing camera: $e');
            }
          }
        }

        if (initializedController == null) return;

        if (!mounted || _isResultStep) {
          await initializedController.dispose();
          return;
        }

        _cameraController = initializedController;
        setState(() {
          _isCameraInitialized = true;
          _flashOn = false;
        });
      } on Exception catch (e) {
        debugPrint('Error initializing camera: $e');
      }
    });
  }

  Future<void> _toggleFlash() async {
    final CameraController? controller = _cameraController;
    if (controller != null && controller.value.isInitialized) {
      try {
        final bool newFlash = !_flashOn;
        await controller.setFlashMode(
          newFlash ? FlashMode.torch : FlashMode.off,
        );
        if (mounted) {
          setState(() => _flashOn = newFlash);
        }
      } on Exception catch (_) {
        if (mounted) {
          setState(() => _flashOn = !_flashOn);
        }
      }
    } else {
      setState(() => _flashOn = !_flashOn);
    }
  }

  Future<void> _takeLivePicture() async {
    if (_isCapturing) return;
    _isCapturing = true;
    try {
      final CameraController? controller = _cameraController;
      if (controller != null && controller.value.isInitialized) {
        try {
          final XFile file = await controller.takePicture();
          final Uint8List bytes = await file.readAsBytes();
          await _enterResultStep(bytes: bytes, path: file.path);

          if (_autoScan) {
            await _runOcr();
          }
          return;
        } on Exception catch (e) {
          debugPrint('Error taking picture: $e');
        }
      }
      // Fallback jika kamera live belum siap
      await _captureOrPick(ImageSource.camera);
    } finally {
      _isCapturing = false;
    }
  }

  Future<void> _captureOrPick(ImageSource source) async {
    _isExternalPickerActive = true;
    _scanAnimationController.stop();
    await _releaseCamera();
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null) {
        if (mounted && !_isResultStep) {
          if (!_scanAnimationController.isAnimating) {
            _scanAnimationController.repeat(reverse: true);
          }
          await _initCamera();
        }
        return;
      }

      final Uint8List bytes = await picked.readAsBytes();
      final String savedPath = kIsWeb
          ? 'data:image/jpeg;base64,${base64Encode(bytes)}'
          : picked.path;

      await _enterResultStep(bytes: bytes, path: savedPath);

      if (_autoScan) {
        await _runOcr();
      }
    } on Exception catch (e) {
      if (mounted && !_isResultStep) {
        if (!_scanAnimationController.isAnimating) {
          _scanAnimationController.repeat(reverse: true);
        }
        await _initCamera();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengambil gambar: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _isExternalPickerActive = false;
    }
  }

  Future<void> _runOcr() async {
    final String? path = _imagePath;
    if (path == null || _isScanning) return;
    final int currentSession = _scanSessionId;
    setState(() => _isScanning = true);

    try {
      final String extractedText = await _exportService.extractText(path);

      if (!mounted || !_isResultStep || currentSession != _scanSessionId) {
        return;
      }
      setState(() {
        _contentController.text = extractedText.isNotEmpty
            ? extractedText
            : 'Teks pada gambar kurang jelas terbaca. Pastikan foto terang dan tidak buram.';
        _isScanning = false;
      });

      _showOcrEditorDialog();
    } on Exception catch (e) {
      if (!mounted || !_isResultStep || currentSession != _scanSessionId) {
        return;
      }
      setState(() {
        _contentController.text = 'Gagal memproses OCR: $e';
        _isScanning = false;
      });
    }
  }

  Future<void> _shareAsPdf() async {
    _isExternalPickerActive = true;
    try {
      await _exportService.shareAsPdf(
        rawTitle: _titleController.text,
        rawContent: _contentController.text,
        category: _selectedCategory,
        imageBytes: _imageBytes,
        rotationTurns: _rotationTurns,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal membuat PDF: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _isExternalPickerActive = false;
    }
  }

  Future<void> _exportAsJpeg() async {
    final Uint8List? bytes = _imageBytes;
    final String? path = _imagePath;
    if (bytes == null || path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada gambar untuk diekspor!'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _isExternalPickerActive = true;
    try {
      await _exportService.exportAsJpeg(
        rawTitle: _titleController.text,
        imagePath: path,
        imageBytes: bytes,
        onReadyMessage: (String message, {required bool isWeb}) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: isWeb ? Colors.green : null,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal ekspor JPEG: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _isExternalPickerActive = false;
    }
  }

  void _showOcrEditorDialog() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.viewInsetsOf(ctx).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
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
                      const SnackBar(
                        content: Text('Teks disalin!'),
                        behavior: SnackBarBehavior.floating,
                      ),
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
                  backgroundColor: AppConstants.primaryBlue,
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

  Future<void> _saveDocument() async {
    if (_isSaving) return;
    _isSaving = true;
    try {
      final String title = _titleController.text.trim().isEmpty
          ? 'Pemindaian Baru'
          : _titleController.text.trim();
      final String content = _contentController.text.trim().isEmpty
          ? 'Catatan hasil pemindaian dokumen.'
          : _contentController.text.trim();

      await _storage.saveFolder(_selectedCategory);

      final NoteModel note = NoteModel(
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
    } finally {
      _isSaving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isResultStep) {
      final CameraController? controller = _cameraController;
      return Scaffold(
        backgroundColor: AppConstants.scannerDarkBg,
        body: SafeArea(
          child: Stack(
            children: <Widget>[
              Center(
                child: Container(
                  margin: const EdgeInsets.only(
                    left: 28,
                    right: 28,
                    top: 60,
                    bottom: 120,
                  ),
                  decoration: BoxDecoration(
                    color: AppConstants.scannerCardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppConstants.scannerLaserBlue.withValues(
                        alpha: 0.6,
                      ),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        if (_isCameraInitialized && controller != null)
                          SizedBox.expand(
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width:
                                    controller.value.previewSize?.height ?? 1,
                                height:
                                    controller.value.previewSize?.width ?? 1,
                                child: CameraPreview(
                                  controller,
                                  key: ObjectKey(controller),
                                ),
                              ),
                            ),
                          )
                        else
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(
                                Icons.document_scanner_outlined,
                                size: 64,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Arahkan ke teks atau dokumen\nlalu tekan tombol rana di bawah',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        AnimatedBuilder(
                          animation: _scanAnimation,
                          builder: (BuildContext context, Widget? child) {
                            return Align(
                              alignment: Alignment(0, _scanAnimation.value),
                              child: child,
                            );
                          },
                          child: Container(
                            height: 3,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: AppConstants.scannerLaserBlue,
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: AppConstants.scannerLaserBlue
                                      .withValues(alpha: 0.8),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
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
                  children: <Widget>[
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
                bottom: 30,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      GestureDetector(
                        onTap: () => _captureOrPick(ImageSource.gallery),
                        child: const SizedBox(
                          width: 60,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.photo_library_outlined,
                                color: Colors.white,
                                size: 28,
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Gallery',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
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
                      SizedBox(
                        width: 60,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Switch(
                              value: _autoScan,
                              activeThumbColor: AppConstants.accentCyan,
                              onChanged: (bool val) =>
                                  setState(() => _autoScan = val),
                            ),
                            const Text(
                              'Auto-Scan',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final int previewCacheSize =
        (270 * MediaQuery.devicePixelRatioOf(context)).round();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: _returnToCameraStep,
        ),
        actions: <Widget>[
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: Colors.black87),
            onSelected: (String value) {
              if (value == 'edit_text') {
                _showOcrEditorDialog();
              } else if (value == 'copy_text') {
                Clipboard.setData(
                  ClipboardData(text: _contentController.text),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Teks catatan disalin!'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } else if (value == 'retake') {
                _returnToCameraStep();
              }
            },
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'edit_text',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.edit_note, size: 20),
                    SizedBox(width: 8),
                    Text('Edit Teks Manual'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'copy_text',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.copy_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Salin Hasil Teks'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'retake',
                child: Row(
                  children: <Widget>[
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
          children: <Widget>[
            Container(
              width: double.infinity,
              height: 270,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppConstants.previewCanvasBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: RotatedBox(
                  quarterTurns: _rotationTurns,
                  child: Container(
                    width: 190,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: _imageBytes != null
                        ? Image.memory(
                            _imageBytes!,
                            cacheWidth: previewCacheSize,
                            fit: BoxFit.contain,
                          )
                        : (_imagePath != null && !kIsWeb
                              ? Image.file(
                                  File(_imagePath!),
                                  cacheWidth: previewCacheSize,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Center(
                                    child: Icon(Icons.description, size: 48),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.description, size: 48),
                                )),
                  ),
                ),
              ),
            ),
            if (_isScanning) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(color: AppConstants.accentCyan),
              const SizedBox(height: 6),
              const Text(
                'Sedang membaca teks dari foto secara otomatis...',
                style: TextStyle(fontSize: 12, color: AppConstants.accentCyan),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Nama Dokumen',
                suffixIcon: Icon(Icons.edit_outlined, size: 20),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: AppConstants.inputBorder,
                enabledBorder: AppConstants.inputBorder,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey<String>('$_selectedCategory:$_dropdownResetNonce'),
              initialValue: _categories.contains(_selectedCategory)
                  ? _selectedCategory
                  : null,
              decoration: InputDecoration(
                labelText: 'Folder Dokumen',
                prefixIcon: const Icon(
                  Icons.folder_outlined,
                  color: AppConstants.accentCyan,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(
                    Icons.create_new_folder_outlined,
                    color: AppConstants.accentCyan,
                  ),
                  tooltip: 'Buat Folder Baru',
                  onPressed: _showAddFolderDialog,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: AppConstants.inputBorder,
                enabledBorder: AppConstants.inputBorder,
              ),
              items: <DropdownMenuItem<String>>[
                ..._categories.map(
                  (String c) =>
                      DropdownMenuItem<String>(value: c, child: Text(c)),
                ),
                const DropdownMenuItem<String>(
                  value: '__new_folder__',
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.add_circle_outline,
                        color: AppConstants.primaryBlue,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '+ Buat Folder Baru...',
                        style: TextStyle(
                          color: AppConstants.primaryBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              onChanged: (String? val) {
                if (val == '__new_folder__') {
                  // Reset dropdown ke kategori aktif terlebih dahulu, lalu buka modal
                  setState(() => _dropdownResetNonce++);
                  _showAddFolderDialog();
                } else if (val != null) {
                  setState(() => _selectedCategory = val);
                }
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _shareAsPdf,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.primaryBlue,
                      side: const BorderSide(color: AppConstants.primaryBlue),
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
                      foregroundColor: AppConstants.primaryBlue,
                      side: const BorderSide(color: AppConstants.primaryBlue),
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
                  foregroundColor: AppConstants.primaryBlue,
                  side: const BorderSide(color: AppConstants.primaryBlue),
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
                  backgroundColor: AppConstants.primaryBlue,
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
