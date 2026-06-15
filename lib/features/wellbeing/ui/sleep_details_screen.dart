import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sleep_models.dart';
import '../service/sleep_repository.dart';
import 'sleep_history_screen.dart';
import 'sleep_settings_screen.dart';

/// Dedicated Sleep Details screen containing all sleep analytics,
/// insights, history access, and edit functionality.
class SleepDetailsScreen extends StatefulWidget {
  const SleepDetailsScreen({
    super.key,
    required this.repository,
    this.initialData,
  });

  final SleepRepository repository;
  final SleepDashboardData? initialData;

  @override
  State<SleepDetailsScreen> createState() => _SleepDetailsScreenState();
}

class _SleepDetailsScreenState extends State<SleepDetailsScreen> {
  late Future<SleepDashboardData> _future;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _future = Future.value(widget.initialData!);
    } else {
      _future = widget.repository.getDashboardData();
    }
  }

  void _refresh() {
    setState(() {
      _future = widget.repository.getDashboardData();
    });
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SleepSettingsScreen(repository: widget.repository),
      ),
    );
    if (updated == true && mounted) _refresh();
  }

  Future<void> _openHistory() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SleepHistoryScreen(repository: widget.repository),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _logSleep([SleepRecord? record]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _SleepEditDialog(
        repository: widget.repository,
        initialRecord: record,
      ),
    );
    if (saved == true && mounted) {
      _refresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sleep record saved.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sleep Details'),
        actions: [
          IconButton(
            tooltip: 'Sleep settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: FutureBuilder<SleepDashboardData>(
        future: _future,
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

          final data = snapshot.data!;
          final lastNight = data.lastNight;
          final analytics = data.analytics;
          final goalProgress = lastNight == null
              ? 0
              : ((lastNight.durationMinutes / data.settings.sleepGoalMinutes) *
                        100)
                    .round()
                    .clamp(0, 100);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Last Night Summary
              _SectionCard(
                title: 'Last Night',
                icon: Icons.bedtime_outlined,
                child: lastNight == null
                    ? const _EmptyState(
                        message: 'No sleep record for today yet.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatSleepDuration(lastNight.durationMinutes),
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _MetricChip(
                                label: 'Bedtime',
                                value: formatSleepClock(lastNight.sleepTime),
                              ),
                              const SizedBox(width: 16),
                              _MetricChip(
                                label: 'Wake time',
                                value: formatSleepClock(lastNight.wakeTime),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),

              // Metrics: Sleep Score, Consistency, Goal
              _SectionCard(
                title: 'Metrics',
                icon: Icons.analytics_outlined,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _ScoreWidget(
                            label: 'Sleep Score',
                            score: analytics.sleepScore,
                            sublabel: analytics.sleepScoreLabelText,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ScoreWidget(
                            label: 'Consistency',
                            score: analytics.consistencyScore,
                            sublabel: analytics.consistencyLabel,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _GoalProgressBar(
                      progress: goalProgress,
                      currentMinutes: lastNight?.durationMinutes ?? 0,
                      goalMinutes: data.settings.sleepGoalMinutes,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Weekly Analytics
              _SectionCard(
                title: 'Weekly Analytics',
                icon: Icons.show_chart,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _MetricChip(
                            label: 'Avg Sleep',
                            value: formatSleepDuration(analytics.averageSleep),
                          ),
                        ),
                        Expanded(
                          child: _MetricChip(
                            label: 'Avg Bedtime',
                            value: analytics.averageBedtime != null
                                ? formatSleepClock(analytics.averageBedtime!)
                                : '--',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _MetricChip(
                            label: 'Avg Wake',
                            value: analytics.averageWakeTime != null
                                ? formatSleepClock(analytics.averageWakeTime!)
                                : '--',
                          ),
                        ),
                        Expanded(
                          child: _MetricChip(
                            label: 'Goal Met',
                            value: '${analytics.goalMetDays}/7 days',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Insights
              _SectionCard(
                title: 'Insights',
                icon: Icons.lightbulb_outline,
                child: analytics.insights.isEmpty
                    ? const _EmptyState(
                        message: 'Log more nights to unlock insights.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final insight in analytics.insights)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.auto_awesome,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(insight)),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openHistory,
                      icon: const Icon(Icons.history),
                      label: const Text('Sleep History'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _logSleep(lastNight),
                      icon: Icon(
                        lastNight == null ? Icons.add : Icons.edit_outlined,
                      ),
                      label: Text(
                        lastNight == null ? 'Log Sleep' : 'Edit Sleep',
                      ),
                    ),
                  ),
                ],
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
// Reusable widgets for the Sleep Details screen
// =============================================================================

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

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
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _ScoreWidget extends StatelessWidget {
  const _ScoreWidget({
    required this.label,
    required this.score,
    required this.sublabel,
  });

  final String label;
  final int score;
  final String sublabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            '$score',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          Text(
            sublabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _GoalProgressBar extends StatelessWidget {
  const _GoalProgressBar({
    required this.progress,
    required this.currentMinutes,
    required this.goalMinutes,
  });

  final int progress;
  final int currentMinutes;
  final int goalMinutes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Goal Progress', style: Theme.of(context).textTheme.bodySmall),
            Text(
              '$progress%',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (progress / 100).clamp(0, 1).toDouble(),
            minHeight: 8,
            backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${formatSleepDuration(currentMinutes)} / ${formatSleepDuration(goalMinutes)}',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
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
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// =============================================================================
// Sleep Edit Dialog (reused from original, simplified)
// =============================================================================

class _SleepEditDialog extends StatefulWidget {
  const _SleepEditDialog({required this.repository, this.initialRecord});

  final SleepRepository repository;
  final SleepRecord? initialRecord;

  @override
  State<_SleepEditDialog> createState() => _SleepEditDialogState();
}

class _SleepEditDialogState extends State<_SleepEditDialog> {
  late DateTime _date;
  late TimeOfDay _sleepTime;
  late TimeOfDay _wakeTime;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final record = widget.initialRecord;
    _date = record?.date ?? DateTime.now();
    _sleepTime = TimeOfDay(
      hour: (record?.sleepTime ?? 23 * 60) ~/ 60,
      minute: (record?.sleepTime ?? 23 * 60) % 60,
    );
    _wakeTime = TimeOfDay(
      hour: (record?.wakeTime ?? 7 * 60) ~/ 60,
      minute: (record?.wakeTime ?? 7 * 60) % 60,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickSleepTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _sleepTime,
    );
    if (picked != null) setState(() => _sleepTime = picked);
  }

  Future<void> _pickWakeTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _wakeTime,
    );
    if (picked != null) setState(() => _wakeTime = picked);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final sleepMinutes = _sleepTime.hour * 60 + _sleepTime.minute;
      final wakeMinutes = _wakeTime.hour * 60 + _wakeTime.minute;
      await widget.repository.upsertRecord(
        date: _date,
        sleepTime: sleepMinutes,
        wakeTime: wakeMinutes,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sleepMinutes = _sleepTime.hour * 60 + _sleepTime.minute;
    final wakeMinutes = _wakeTime.hour * 60 + _wakeTime.minute;
    final duration = calculateSleepDurationMinutes(sleepMinutes, wakeMinutes);

    return AlertDialog(
      title: Text(
        widget.initialRecord == null ? 'Log Sleep' : 'Edit Sleep Record',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date'),
            trailing: Text(DateFormat('EEE, dd MMM').format(_date)),
            onTap: _pickDate,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bedtime'),
            trailing: Text(_sleepTime.format(context)),
            onTap: _pickSleepTime,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Wake time'),
            trailing: Text(_wakeTime.format(context)),
            onTap: _pickWakeTime,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Duration'),
                Text(
                  formatSleepDuration(duration),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
