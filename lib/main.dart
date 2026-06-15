import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'features/wellbeing/service/health_sync_manager.dart';
import 'screens/login_screen.dart';
import 'services/auth_state_manager.dart';
import 'services/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await ThemeService().initialize();
  await HealthSyncManager.instance.initialize();
  runApp(const StudentOS());
}

class StudentOS extends StatelessWidget {
  const StudentOS({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService().themeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'StudentOS',
          themeMode: themeMode,
          theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.blue,
            useMaterial3: true,
            brightness: Brightness.dark,
          ),
          home: const _RootScreen(),
        );
      },
    );
  }
}

class _RootScreen extends StatefulWidget {
  const _RootScreen();

  @override
  State<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<_RootScreen> {
  late Future<bool> _checkLoginFuture;

  @override
  void initState() {
    super.initState();
    _checkLoginFuture = AuthStateManager().isLoggedIn();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkLoginFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Error checking login status')),
          );
        }

        final isLoggedIn = snapshot.data ?? false;
        if (isLoggedIn) {
          return const LoginScreen(skipToAuth: true);
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
