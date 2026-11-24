import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/web_helper.dart';

class ScanExportService {
  const ScanExportService();

  /// Mengekstrak teks dari foto menggunakan ML Kit (mobile) atau Tesseract (web).
  /// Memastikan native TextRecognizer selalu ditutup pada blok finally.
  Future<String> extractText(String imagePath) async {
    if (kIsWeb) {
      return runWebOcr(imagePath);
    }

    final InputImage inputImage = InputImage.fromFilePath(imagePath);
    final TextRecognizer textRecognizer = TextRecognizer(
      script: TextRecognitionScript.latin,
    );
    try {
      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);
      return recognizedText.text;
    } finally {
      await textRecognizer.close();
    }
  }

  /// Membuat dokumen PDF lengkap dengan orientasi putaran foto dan membagikannya.
  Future<void> shareAsPdf({
    required String rawTitle,
    required String rawContent,
    required String category,
    Uint8List? imageBytes,
    int rotationTurns = 0,
  }) async {
    final pw.Document pdf = pw.Document();
    final String docTitle = rawTitle.trim().isEmpty
        ? 'Catatan_PindaiKu.pdf'
        : rawTitle.trim();
    final String ocrText = rawContent.trim().isEmpty
        ? '(Belum ada teks hasil OCR)'
        : rawContent.trim();

    final pw.MemoryImage? pdfImage =
        imageBytes != null ? pw.MemoryImage(imageBytes) : null;
    final int normalizedTurns = rotationTurns % 4;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => <pw.Widget>[
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
            'Folder: $category',
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 16),
          if (pdfImage != null) ...<pw.Widget>[
            pw.Center(
              child: pw.Container(
                height: 280,
                child: normalizedTurns == 0
                    ? pw.Image(pdfImage, fit: pw.BoxFit.contain)
                    : pw.Transform.rotateBox(
                        angle: -normalizedTurns * (math.pi / 2),
                        child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
                      ),
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

    final Uint8List pdfBytes = await pdf.save();
    final String fileName = docTitle.toLowerCase().endsWith('.pdf')
        ? docTitle
        : '$docTitle.pdf';

    await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
  }

  /// Menyiapkan file JPEG untuk diunduh (web) atau dibagikan (Android/iOS).
  Future<void> exportAsJpeg({
    required String rawTitle,
    required String imagePath,
    required Uint8List imageBytes,
    required void Function(String message, {required bool isWeb}) onReadyMessage,
  }) async {
    final String baseName = rawTitle
        .trim()
        .replaceAll('.pdf', '')
        .replaceAll(' ', '_');
    final String fileName = '${baseName.isEmpty ? 'PindaiKu' : baseName}.jpg';

    if (kIsWeb) {
      downloadWebImage(imagePath, fileName);
      onReadyMessage('File $fileName berhasil diunduh!', isWeb: true);
      return;
    }

    final Directory dir = Directory.systemTemp;
    final File file = File('${dir.path}/$fileName');
    await file.writeAsBytes(imageBytes);

    String savedMsg = '';
    try {
      final Directory publicDownloadDir =
          Directory('/storage/emulated/0/Download');
      if (await publicDownloadDir.exists()) {
        final File publicFile = File('${publicDownloadDir.path}/$fileName');
        await publicFile.writeAsBytes(imageBytes);
        savedMsg = ' & tersimpan di folder Download';
      }
    } on Exception catch (_) {
      // Abaikan jika akses folder Download publik dibatasi Scoped Storage OS
    }

    onReadyMessage('File $fileName siap dibagikan$savedMsg!', isWeb: false);

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile(file.path, mimeType: 'image/jpeg', name: fileName),
        ],
        text: 'Catatan JPEG PindaiKu: $fileName',
      ),
    );
  }
}
