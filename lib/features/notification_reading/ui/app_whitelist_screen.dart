import 'package:flutter/material.dart';

import '../service/notification_service.dart';

class AppWhitelistScreen extends StatefulWidget {
  final NotificationService notificationService;
  final bool isFirstTime;
  final VoidCallback? onSkip;

  const AppWhitelistScreen({
    super.key,
    required this.notificationService,
    this.isFirstTime = false,
    this.onSkip,
  });

  @override
  State<AppWhitelistScreen> createState() => _AppWhitelistScreenState();
}

class _AppWhitelistScreenState extends State<AppWhitelistScreen> {
  final Map<String, bool> _selectedApps = {};
  bool _isSaving = false;

  // Common academic and messaging apps
  static const List<Map<String, String>> availableApps = [
    {'id': 'com.whatsapp', 'name': 'WhatsApp', 'icon': '💬'},
    {'id': 'com.google.android.gm', 'name': 'Gmail', 'icon': '📧'},
    {'id': 'org.telegram.messenger', 'name': 'Telegram', 'icon': '📱'},
    {'id': 'com.microsoft.office.outlook', 'name': 'Outlook', 'icon': '📨'},
    {'id': 'com.microsoft.teams', 'name': 'Microsoft Teams', 'icon': '👥'},
    {'id': 'com.google.android.apps.messaging', 'name': 'Google Messages', 'icon': '💭'},
    {'id': 'com.samsung.android.messaging', 'name': 'Samsung Messages', 'icon': '✉️'},
    {'id': 'com.slack', 'name': 'Slack', 'icon': '🔔'},
    {'id': 'com.discord', 'name': 'Discord', 'icon': '🎮'},
  ];

  @override
  void initState() {
    super.initState();
    _initializeApps();
  }

  Future<void> _initializeApps() async {
    try {
      final enabled = await widget.notificationService.getEnabledApps();
      setState(() {
        for (final app in availableApps) {
          _selectedApps[app['id']!] = enabled.contains(app['id']!);
        }
      });
    } catch (e) {
      // Default to all apps enabled
      setState(() {
        for (final app in availableApps) {
          _selectedApps[app['id']!] = true;
        }
      });
    }
  }

  Future<void> _saveChanges() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final selectedIds = _selectedApps.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      await widget.notificationService.setEnabledApps(selectedIds);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App whitelist updated successfully')),
      );

      if (widget.isFirstTime && mounted) {
        Navigator.pop(context, true); // Return true to indicate completion
      } else if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _selectAll() {
    setState(() {
      for (final key in _selectedApps.keys) {
        _selectedApps[key] = true;
      }
    });
  }

  void _deselectAll() {
    setState(() {
      for (final key in _selectedApps.keys) {
        _selectedApps[key] = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select apps to monitor'),
        leading: widget.isFirstTime ? null : const BackButton(),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose which apps StudentOS should monitor for academic notifications',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton.tonal(
                      onPressed: _selectAll,
                      child: const Text('Select all'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: _deselectAll,
                      child: const Text('Deselect all'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: availableApps.length,
              itemBuilder: (context, index) {
                final app = availableApps[index];
                final isSelected = _selectedApps[app['id']!] ?? false;

                return CheckboxListTile(
                  title: Text('${app['icon']} ${app['name']}'),
                  subtitle: Text(app['id']!),
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      _selectedApps[app['id']!] = value ?? false;
                    });
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: _isSaving ? null : _saveChanges,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continue'),
                ),
                if (widget.isFirstTime) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _isSaving
                        ? null
                        : () {
                            if (widget.onSkip != null) {
                              widget.onSkip!();
                            }
                            Navigator.pop(context, false);
                          },
                    child: const Text("I'll do it later"),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
