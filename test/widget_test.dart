import 'package:flutter_test/flutter_test.dart';
import 'package:pindaiku/main.dart';
import 'package:pindaiku/models/note_model.dart';
import 'package:pindaiku/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    StorageService.resetCache();
  });

  group('StorageService & NoteModel tests', () {
    test('Registrasi tidak langsung auto-login dan ubah nama tidak menimpa sandi', () async {
      final StorageService storage = StorageService();

      await storage.registerUser('Budi', 'budi@amikom.ac.id', 'rahasia123');
      expect(await storage.getActiveUser(), isNull);

      final String? loginError =
          await storage.loginUser('budi@amikom.ac.id', 'rahasia123');
      expect(loginError, isNull);
      expect((await storage.getActiveUser())?.name, 'Budi');

      // Ubah nama tampilan dan pastikan kata sandi asli tetap berlaku
      await storage.updateUserName('Budi Santoso');
      expect((await storage.getActiveUser())?.name, 'Budi Santoso');

      await storage.logoutUser();
      expect(await storage.getActiveUser(), isNull);

      expect(
        await storage.loginUser('budi@amikom.ac.id', '123456'),
        isNotNull,
      );
      expect(
        await storage.loginUser('budi@amikom.ac.id', 'rahasia123'),
        isNull,
      );
    });

    test('Menyimpan dan memuat NoteModel beserta indeks pencarian bekerja akurat', () async {
      final StorageService storage = StorageService();
      final NoteModel sample = NoteModel(
        id: '101',
        title: 'Catatan Kuliah Mobile',
        subject: 'Pemrograman Mobile',
        category: 'Kampus',
        content: 'Belajar optimasi Flutter dan Dart',
        createdAt: DateTime(2026, 11, 24),
      );

      await storage.saveNotes(<NoteModel>[sample]);
      final List<NoteModel> loaded = await storage.getNotes();

      expect(loaded.length, 1);
      expect(loaded.first.title, 'Catatan Kuliah Mobile');
      expect(loaded.first.searchIndex.contains('optimasi flutter'), isTrue);

      final NoteModel moved = loaded.first.copyWith(category: 'Dokumen');
      expect(moved.category, 'Dokumen');
      expect(moved.id, '101');
    });
  });

  testWidgets('PindaiKuApp menampilkan halaman Login saat belum ada sesi aktif', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PindaiKuApp());
    await tester.pumpAndSettle();

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Kata Sandi'), findsOneWidget);
    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('Daftar'), findsOneWidget);
  });
}
