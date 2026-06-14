import 'package:flutter/material.dart';

import 'login_screen.dart';
import '../features/notification_reading/service/notification_service.dart';
import '../features/notification_reading/ui/whitelist_settings_screen.dart';
import '../features/notification_reading/ui/app_whitelist_screen.dart';
import '../services/auth_state_manager.dart';
import '../services/google_auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.notificationService});

  final NotificationService notificationService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthStateManager _authStateManager = AuthStateManager();
  final GoogleAuthService _googleAuthService = GoogleAuthService();
  bool _isLoggingOut = false;

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out of StudentOS?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isLoggingOut = true;
    });

    try {
      await _googleAuthService.signOut();
      await _authStateManager.clearUser();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logged out successfully')),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout failed: $e')),
      );
      setState(() {
        _isLoggingOut = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          // Notifications section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Notifications',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            title: const Text('Monitor apps'),
            subtitle: const Text('Choose which apps to monitor for notifications'),
            leading: const Icon(Icons.apps),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AppWhitelistScreen(
                    notificationService: widget.notificationService,
                    isFirstTime: false,
                  ),
                ),
              );
            },
          ),
          ListTile(
            title: const Text('WhatsApp whitelist'),
            subtitle: const Text('Manage which WhatsApp groups and people to monitor'),
            leading: const Icon(Icons.filter_alt),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WhitelistSettingsScreen(
                    notificationService: widget.notificationService,
                  ),
                ),
              );
            },
          ),
          const Divider(height: 24),
          // Account section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Account',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            title: const Text('Log out'),
            subtitle: const Text('Sign out from StudentOS'),
            leading: const Icon(Icons.logout),
            enabled: !_isLoggingOut,
            onTap: _isLoggingOut ? null : _logout,
          ),
          if (_isLoggingOut)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
