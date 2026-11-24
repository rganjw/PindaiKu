import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/storage_service.dart';
import 'utils/app_constants.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: AppConstants.primaryBlue),
        useMaterial3: true,
      ),
      home: const _InitialAuthGate(),
    );
  }
}

class _InitialAuthGate extends StatefulWidget {
  const _InitialAuthGate();

  @override
  State<_InitialAuthGate> createState() => _InitialAuthGateState();
}

class _InitialAuthGateState extends State<_InitialAuthGate> {
  late final Future<ActiveUser?> _activeUserFuture;

  @override
  void initState() {
    super.initState();
    _activeUserFuture = StorageService().getActiveUser();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ActiveUser?>(
      future: _activeUserFuture,
      builder: (BuildContext context, AsyncSnapshot<ActiveUser?> snapshot) {
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
    );
  }
}
