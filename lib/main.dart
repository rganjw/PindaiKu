import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/storage_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PindaiKuApp());
}

class PindaiKuApp extends StatelessWidget {
  const PindaiKuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PindaiKu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1967D2)),
        useMaterial3: true,
      ),
      home: FutureBuilder(
        future: StorageService().getActiveUser(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.data != null) {
            return const HomeScreen();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
