import 'package:flutter/material.dart';

import '../models/hydration_models.dart';
import '../service/hydration_service.dart';

/// Dedicated Hydration Details screen containing goal configuration,
/// reminder settings, weekly averages, streaks, and consumption history.
class HydrationDetailsScreen extends StatefulWidget {
  const HydrationDetailsScreen({
    super.key,
    required this.hydrationService,
    this.initialSummary,
  });

  final HydrationService hydrationService;
  final HydrationSummary? initialSummary;

  @override
  State<HydrationDetailsScreen> createState() => _HydrationDetailsScreenState();
}

class _HydrationDetailsScreenState extends State<HydrationDetailsScreen> {
  late Future<HydrationSummary> _summaryFuture;

  @override
  void initState() {
    super.initState();
    if (widget.initialSummary != null) {
      _summaryFuture = Future.value(widget.initialSummary!);
    } else {
      _summaryFuture = widget.hydrationService.getSummary();
    }
  }

  void _refresh() {
    setState(() {
      _summaryFuture = widget.hydrationService.getSummary();
    });
  }

  Future<void> _addWater([int amount = 250]) async {
    await widget.hydrationService.addWater(amountMl: amount);
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Added $amount ml')));
  }

  Future<void> _openSettings(HydrationSettings settings) async {
    final updated = await showDialog<HydrationSettings>(
      context: context,
      builder: (context) => _HydrationSettingsDialog(settings: settings),
    );
    if (updated == null) return;
    await widget.hydrationService.saveSettings(updated);
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updated.enabled
              ? 'Hydration reminders enabled.'
              : 'Hydration reminders disabled.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hydration Details')),
      body: FutureBuilder<HydrationSummary>(
        future: _summaryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 12),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            );
          }

          final summary = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Today's Progress Hero
              _ProgressHeroCard(summary: summary, onAddWater: _addWater),
              const SizedBox(height: 16),

              // Quick Add Buttons
              _QuickAddSection(onAdd: _addWater),
              const SizedBox(height: 16),

              // Stats
              _StatsCard(summary: summary),
              const SizedBox(height: 16),

              // Reminder Settings
              _ReminderCard(
                settings: summary.settings,
                onOpenSettings: () => _openSettings(summary.settings),
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// Progress Hero Card
// =============================================================================

class _ProgressHeroCard extends StatelessWidget {
  const _ProgressHeroCard({required this.summary, required this.onAddWater});

  final HydrationSummary summary;
  final VoidCallback onAddWater;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentLiters = summary.today.amountMl / 1000;
    final goalLiters = summary.today.goalMl / 1000;

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: summary.progress,
                    strokeWidth: 12,
                    backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                    color: colorScheme.primary,
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${summary.percentComplete}%',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'complete',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '${currentLiters.toStringAsFixed(1)} L / ${goalLiters.toStringAsFixed(1)} L',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              summary.remainingMl > 0
                  ? '${_formatMl(summary.remainingMl)} remaining'
                  : 'Goal reached! 🎉',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAddWater,
              icon: const Icon(Icons.add),
              label: const Text('Log 250 ml'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Quick Add Section
// =============================================================================

class _QuickAddSection extends StatelessWidget {
  const _QuickAddSection({required this.onAdd});

  final void Function(int amount) onAdd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Add',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _QuickAddChip(label: '150 ml', onTap: () => onAdd(150)),
                _QuickAddChip(label: '250 ml', onTap: () => onAdd(250)),
                _QuickAddChip(label: '500 ml', onTap: () => onAdd(500)),
                _QuickAddChip(label: '750 ml', onTap: () => onAdd(750)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAddChip extends StatelessWidget {
  const _QuickAddChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.water_drop_outlined, size: 16),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

// =============================================================================
// Stats Card
// =============================================================================

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.summary});

  final HydrationSummary summary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Statistics',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _StatItem(
                    label: 'Weekly Average',
                    value: _formatMl(summary.weeklyAverageMl.round()),
                    icon: Icons.bar_chart,
                  ),
                ),
                Expanded(
                  child: _StatItem(
                    label: 'Completion Rate',
                    value: '${(summary.goalCompletionRate * 100).round()}%',
                    icon: Icons.check_circle_outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatItem(
                    label: 'Current Streak',
                    value: '${summary.streakDays} days',
                    icon: Icons.local_fire_department,
                  ),
                ),
                Expanded(
                  child: _StatItem(
                    label: 'Daily Goal',
                    value: _formatMl(summary.today.goalMl),
                    icon: Icons.flag_outlined,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: colorScheme.primary.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Reminder Card
// =============================================================================

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.settings, required this.onOpenSettings});

  final HydrationSettings settings;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onOpenSettings,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                settings.enabled
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reminders',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      settings.enabled
                          ? '${_formatTime(settings.startMinutes)} – ${_formatTime(settings.endMinutes)}, every ${settings.frequencyMinutes} min'
                          : 'Tap to configure reminders',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Hydration Settings Dialog
// =============================================================================

class _HydrationSettingsDialog extends StatefulWidget {
  const _HydrationSettingsDialog({required this.settings});

  final HydrationSettings settings;

  @override
  State<_HydrationSettingsDialog> createState() =>
      _HydrationSettingsDialogState();
}

class _HydrationSettingsDialogState extends State<_HydrationSettingsDialog> {
  late bool _enabled;
  late bool _soundEnabled;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late double _frequencyMinutes;
  late final TextEditingController _goalController;

  @override
  void initState() {
    super.initState();
    final settings = widget.settings;
    _enabled = settings.enabled;
    _soundEnabled = settings.soundEnabled;
    _startTime = TimeOfDay(
      hour: settings.startMinutes ~/ 60,
      minute: settings.startMinutes % 60,
    );
    _endTime = TimeOfDay(
      hour: settings.endMinutes ~/ 60,
      minute: settings.endMinutes % 60,
    );
    _frequencyMinutes = settings.frequencyMinutes.toDouble();
    _goalController = TextEditingController(
      text: (settings.dailyGoalMl / 1000).toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) setState(() => _endTime = picked);
  }

  void _save() {
    final goalLiters = double.tryParse(_goalController.text.trim()) ?? 2;
    final goalMl = (goalLiters * 1000).round().clamp(250, 10000);
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;

    if (endMinutes <= startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
      return;
    }

    Navigator.pop(
      context,
      HydrationSettings(
        enabled: _enabled,
        dailyGoalMl: goalMl,
        startMinutes: startMinutes,
        endMinutes: endMinutes,
        frequencyMinutes: _frequencyMinutes.round(),
        soundEnabled: _soundEnabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Hydration Settings'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable reminders'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            TextField(
              controller: _goalController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Daily goal',
                suffixText: 'liters',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Start time'),
              trailing: Text(_startTime.format(context)),
              onTap: _pickStart,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('End time'),
              trailing: Text(_endTime.format(context)),
              onTap: _pickEnd,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Every ${_frequencyMinutes.round()} minutes'),
              subtitle: Slider(
                value: _frequencyMinutes,
                min: 15,
                max: 240,
                divisions: 15,
                label: '${_frequencyMinutes.round()} min',
                onChanged: (value) => setState(() => _frequencyMinutes = value),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reminder sound'),
              value: _soundEnabled,
              onChanged: (value) => setState(() => _soundEnabled = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// =============================================================================
// Helpers
// =============================================================================

String _formatMl(int amountMl) {
  if (amountMl >= 1000) {
    final liters = amountMl / 1000;
    return '${liters.toStringAsFixed(liters == liters.roundToDouble() ? 0 : 1)} L';
  }
  return '$amountMl ml';
}

String _formatTime(int minutes) {
  final hour = minutes ~/ 60;
  final minute = minutes % 60;
  final suffix = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
}
