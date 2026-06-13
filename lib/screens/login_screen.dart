import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import '../features/notification_reading/service/notification_service.dart';
import '../services/google_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GoogleAuthService _authService = GoogleAuthService();
  final NotificationService _notificationService = NotificationService();
  bool _isSigningIn = false;
  String? _signInError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _askForNotificationAccessIfNeeded();
    });
  }

  Future<void> _askForNotificationAccessIfNeeded() async {
    final shouldAsk = await _notificationService.shouldAsk();
    if (!mounted || !shouldAsk) return;

    final action = await showDialog<_NotificationPermissionAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable notification access?'),
        content: const Text(
          'StudentOS needs notification access to read supported academic notifications and turn them into tasks.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _NotificationPermissionAction.notNow),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              _NotificationPermissionAction.dontAskAgain,
            ),
            child: const Text("Don't ask again"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _NotificationPermissionAction.openSettings,
            ),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    switch (action) {
      case _NotificationPermissionAction.openSettings:
        await _notificationService.openSettings();
      case _NotificationPermissionAction.dontAskAgain:
        await _notificationService.markDontAskAgain();
      case _NotificationPermissionAction.notNow:
      case null:
        break;
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isSigningIn = true;
      _signInError = null;
    });

    try {
      final user = await _authService.signIn();
      if (!mounted) return;

      if (user == null) {
        _showSignInError('Google sign-in was cancelled.');
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DashboardScreen(user: user)),
      );
    } on GoogleAuthException catch (e) {
      if (mounted) {
        _showSignInError(e.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });
      }
    }
  }

  void _showSignInError(String message) {
    setState(() {
      _signInError = message;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.calendar_month, size: 80),

              const SizedBox(height: 20),

              const Text(
                "StudentOS",
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              const Text("Organize your academic life"),

              const SizedBox(height: 40),

              if (_signInError != null) ...[
                Text(
                  _signInError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
              ],

              ElevatedButton(
                onPressed: _isSigningIn ? null : _signInWithGoogle,
                child: Text(
                  _isSigningIn ? "Signing in..." : "Sign in with Google",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _NotificationPermissionAction { openSettings, notNow, dontAskAgain }
