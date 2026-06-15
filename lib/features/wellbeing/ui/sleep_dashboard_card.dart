import 'package:flutter/material.dart';

import '../models/sleep_models.dart';
import '../service/sleep_repository.dart';
import 'sleep_history_screen.dart';
import 'sleep_settings_screen.dart';

class SleepDashboardCard extends StatefulWidget {
  const SleepDashboardCard({super.key, this.repository});

  final SleepRepository? repository;

  @override
  State<SleepDashboardCard> createState() => _SleepDashboardCardState();
}

class _SleepDashboardCardState extends State<SleepDashboardCard> {
  late final SleepRepository _repository;
  late Future<SleepDashboardData> _future;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SleepRepository();
    _future = _repository.getDashboardData();
  }

  void _refresh() {
    setState(() {
      _future = _repository.getDashboardData();
    });
  }

  Future<void> _logSleep([SleepRecord? record]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _SleepLogDialog(repository: _repository, initialRecord: record),
    );
    if (saved != true || !mounted) return;
    _refresh();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sleep record saved.')));
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SleepSettingsScreen(repository: _repository),
      ),
    );
    if (updated == true && mounted) _refresh();
  }

  Future<void> _openHistory() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SleepHistoryScreen(repository: _repository),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SleepDashboardData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Sleep insights unavailable'),
              subtitle: Text('${snapshot.error}'),
              trailing: IconButton(
                tooltip: 'Retry',
                icon: const Icon(Icons.refresh),
                onPressed: _refresh,
              ),
            ),
          );
        }

        final data = snapshot.data!;
        final lastNight = data.lastNight;
        final goalProgress = lastNight == null
            ? 0.0
            : (lastNight.durationMinutes / data.settings.sleepGoalMinutes)
                  .clamp(0, 1)
                  .toDouble();
        final achievement = (goalProgress * 100).round();

        return Card(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.blue.shade50,
                      foregroundColor: Colors.blue.shade700,
                      child: const Icon(Icons.bedtime_outlined),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sleep insights',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sleep settings',
                      onPressed: _openSettings,
                      icon: const Icon(Icons.tune),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SleepSummarySection(
                  lastNight: lastNight,
                  onLogSleep: () => _logSleep(lastNight),
                ),
                const SizedBox(height: 14),
                _GoalProgressSection(
                  currentMinutes: lastNight?.durationMinutes ?? 0,
                  goalMinutes: data.settings.sleepGoalMinutes,
                  achievement: achievement,
                  progress: goalProgress,
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 520;
                    final cards = [
                      _ScoreTile(
                        title: 'Sleep Score',
                        score: data.analytics.sleepScore,
                        label: data.analytics.sleepScoreLabelText,
                        icon: Icons.nightlight_round,
                      ),
                      _ScoreTile(
                        title: 'Consistency Score',
                        score: data.analytics.consistencyScore,
                        label: data.analytics.consistencyLabel,
                        icon: Icons.show_chart,
                      ),
                    ];
                    if (wide) {
                      return Row(
                        children: [
                          Expanded(child: cards[0]),
                          const SizedBox(width: 10),
                          Expanded(child: cards[1]),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        cards[0],
                        const SizedBox(height: 10),
                        cards[1],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                _WeeklyAnalyticsSection(analytics: data.analytics),
                const SizedBox(height: 14),
                _InsightsSection(insights: data.analytics.insights),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openHistory,
                        icon: const Icon(Icons.history),
                        label: const Text('Sleep history'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _logSleep(lastNight),
                        icon: Icon(lastNight == null ? Icons.add : Icons.edit),
                        label: Text(lastNight == null ? 'Log sleep' : 'Edit'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SleepSummarySection extends StatelessWidget {
  const _SleepSummarySection({
    required this.lastNight,
    required this.onLogSleep,
  });

  final SleepRecord? lastNight;
  final VoidCallback onLogSleep;

  @override
  Widget build(BuildContext context) {
    if (lastNight == null) {
      return _SoftPanel(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Last Night'),
          subtitle: const Text('No sleep record logged for today yet.'),
          trailing: TextButton(onPressed: onLogSleep, child: const Text('Log')),
        ),
      );
    }

    return _SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Last Night', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            formatSleepDuration(lastNight!.durationMinutes),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _MiniMetric(
                label: 'Sleep Time',
                value: formatSleepClock(lastNight!.sleepTime),
              ),
              _MiniMetric(
                label: 'Wake Time',
                value: formatSleepClock(lastNight!.wakeTime),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalProgressSection extends StatelessWidget {
  const _GoalProgressSection({
    required this.currentMinutes,
    required this.goalMinutes,
    required this.achievement,
    required this.progress,
  });

  final int currentMinutes;
  final int goalMinutes;
  final int achievement;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return _SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Goal Progress')),
              Text(
                '$achievement%',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.blue.shade50,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _MiniMetric(
                label: 'Current',
                value: formatSleepDuration(currentMinutes),
              ),
              _MiniMetric(
                label: 'Goal',
                value: formatSleepDuration(goalMinutes),
              ),
              _MiniMetric(label: 'Achievement', value: '$achievement%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeeklyAnalyticsSection extends StatelessWidget {
  const _WeeklyAnalyticsSection({required this.analytics});

  final SleepAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    return _SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weekly Analytics',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _MiniMetric(
                label: 'Average Sleep',
                value: formatSleepDuration(analytics.averageSleep),
              ),
              _MiniMetric(
                label: 'Avg Bedtime',
                value: analytics.averageBedtime == null
                    ? '--'
                    : formatSleepClock(analytics.averageBedtime!),
              ),
              _MiniMetric(
                label: 'Avg Wake',
                value: analytics.averageWakeTime == null
                    ? '--'
                    : formatSleepClock(analytics.averageWakeTime!),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InsightsSection extends StatelessWidget {
  const _InsightsSection({required this.insights});

  final List<String> insights;

  @override
  Widget build(BuildContext context) {
    return _SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Insights', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          for (final insight in insights)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.circle, size: 7, color: Colors.blue.shade300),
                  const SizedBox(width: 8),
                  Expanded(child: Text(insight)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ScoreTile extends StatelessWidget {
  const _ScoreTile({
    required this.title,
    required this.score,
    required this.label,
    required this.icon,
  });

  final String title;
  final int score;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _SoftPanel(
      child: Row(
        children: [
          Icon(icon, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  '$score/100',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(label),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 104),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SoftPanel extends StatelessWidget {
  const _SoftPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.10)),
      ),
      child: child,
    );
  }
}

class _SleepLogDialog extends StatefulWidget {
  const _SleepLogDialog({
    required this.repository,
    required this.initialRecord,
  });

  final SleepRepository repository;
  final SleepRecord? initialRecord;

  @override
  State<_SleepLogDialog> createState() => _SleepLogDialogState();
}

class _SleepLogDialogState extends State<_SleepLogDialog> {
  late DateTime _date;
  late TimeOfDay _sleepTime;
  late TimeOfDay _wakeTime;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final record = widget.initialRecord;
    _date = record?.date ?? DateTime.now();
    _sleepTime = _timeOfDay(record?.sleepTime ?? 23 * 60);
    _wakeTime = _timeOfDay(record?.wakeTime ?? 7 * 60);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    final existing = await widget.repository.getRecordForDate(picked);
    if (!mounted) return;
    setState(() {
      _date = picked;
      if (existing != null) {
        _sleepTime = _timeOfDay(existing.sleepTime);
        _wakeTime = _timeOfDay(existing.wakeTime);
      }
    });
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
      await widget.repository.upsertRecord(
        date: _date,
        sleepTime: _minutesOfDay(_sleepTime),
        wakeTime: _minutesOfDay(_wakeTime),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save sleep record: $e')),
      );
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = calculateSleepDurationMinutes(
      _minutesOfDay(_sleepTime),
      _minutesOfDay(_wakeTime),
    );

    return AlertDialog(
      title: Text(widget.initialRecord == null ? 'Log sleep' : 'Edit sleep'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date'),
            trailing: Text(sleepDateKey(_date)),
            onTap: _pickDate,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sleep Time'),
            trailing: Text(_sleepTime.format(context)),
            onTap: _pickSleepTime,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Wake Time'),
            trailing: Text(_wakeTime.format(context)),
            onTap: _pickWakeTime,
          ),
          const SizedBox(height: 8),
          _SoftPanel(
            child: Row(
              children: [
                const Expanded(child: Text('Duration')),
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

TimeOfDay _timeOfDay(int minutes) {
  return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}

int _minutesOfDay(TimeOfDay value) {
  return value.hour * 60 + value.minute;
}
