import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/activity_models.dart';
import '../service/activity_nudge_service.dart';
import '../service/activity_repository.dart';
import '../service/health_connect_service.dart';
import '../service/health_sync_manager.dart';
import '../service/sleep_repository.dart';
import 'health_connect_debug_screen.dart';

/// Dedicated Activity & Movement details screen.
class ActivityDetailsScreen extends StatefulWidget {
  const ActivityDetailsScreen({
    super.key,
    required this.repository,
    this.initialData,
  });

  final ActivityRepository repository;
  final ActivityDashboardData? initialData;

  @override
  State<ActivityDetailsScreen> createState() => _ActivityDetailsScreenState();
}

class _ActivityDetailsScreenState extends State<ActivityDetailsScreen> {
  late Future<ActivityDashboardData> _future;
  final ActivityNudgeEngine _nudgeEngine = ActivityNudgeEngine();
  final HealthConnectService _hcService = HealthConnectService.instance;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _future = Future.value(widget.initialData!);
    } else {
      _future = _syncAndLoad();
    }
  }

  Future<ActivityDashboardData> _syncAndLoad() async {
    // Sync on screen open
    await HealthSyncManager.instance.performManualSync(
      activityRepository: widget.repository,
      sleepRepository: SleepRepository(),
    );
    return widget.repository.getDashboardData();
  }

  void _refresh() {
    setState(() {
      _future = _syncAndLoad();
    });
  }

  Future<void> _logSteps() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _LogStepsDialog(repository: widget.repository),
    );
    if (saved == true && mounted) {
      _refresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Steps logged.')));
    }
  }

  Future<void> _changeGoal() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _GoalSettingsDialog(repository: widget.repository),
    );
    if (saved == true && mounted) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity & Movement'),
        actions: [
          if (kDebugMode)
            IconButton(
              tooltip: 'Health Data Debug',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const HealthConnectDebugScreen(),
                ),
              ),
              icon: const Icon(Icons.bug_report_outlined),
            ),
          IconButton(
            tooltip: 'Set goal',
            onPressed: _changeGoal,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: FutureBuilder<ActivityDashboardData>(
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
          final analytics = data.analytics;
          final nudge = _nudgeEngine.getTopNudge(data: data);

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Today's Activity
                _SectionCard(
                  title: "Today's Activity",
                  icon: Icons.directions_walk,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatStepsWithComma(data.todaySteps),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'steps',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _GoalProgressBar(
                        progress: data.goalPercentage,
                        currentSteps: data.todaySteps,
                        goalSteps: data.goal.dailyStepGoal,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Activity Score
                _SectionCard(
                  title: 'Activity Score',
                  icon: Icons.analytics_outlined,
                  child: Row(
                    children: [
                      Expanded(
                        child: _ScoreWidget(
                          score: analytics.activityScore,
                          label: analytics.scoreLabelText,
                          explanation: activityScoreExplanation(
                            analytics.activityScore,
                            analytics.trendDirection,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _TrendWidget(
                          direction: analytics.trendDirection,
                          description: analytics.trendDescription,
                        ),
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
                              label: 'Avg Steps',
                              value: formatStepsWithComma(
                                analytics.averageSteps,
                              ),
                            ),
                          ),
                          Expanded(
                            child: _MetricChip(
                              label: 'Goal Met',
                              value:
                                  '${analytics.goalMetDays}/${analytics.totalDaysTracked} days',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _MetricChip(
                              label: 'Best Day',
                              value: analytics.highestDay != null
                                  ? '${DateFormat('EEE').format(analytics.highestDay!.date)} · ${formatStepsWithComma(analytics.highestDay!.steps)}'
                                  : '--',
                            ),
                          ),
                          Expanded(
                            child: _MetricChip(
                              label: 'Lowest Day',
                              value: analytics.lowestDay != null
                                  ? '${DateFormat('EEE').format(analytics.lowestDay!.date)} · ${formatStepsWithComma(analytics.lowestDay!.steps)}'
                                  : '--',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _MetricChip(
                              label: 'Achievement',
                              value:
                                  '${(analytics.goalAchievementRate * 100).round()}%',
                            ),
                          ),
                          Expanded(
                            child: _MetricChip(
                              label: 'Prev Week Avg',
                              value: analytics.previousWeekAverage > 0
                                  ? formatStepsWithComma(
                                      analytics.previousWeekAverage,
                                    )
                                  : '--',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Weekly Bar Chart (visual)
                if (data.records.isNotEmpty)
                  _SectionCard(
                    title: 'This Week',
                    icon: Icons.bar_chart_rounded,
                    child: _WeeklyBarChart(
                      records: data.records,
                      goal: data.goal,
                    ),
                  ),
                if (data.records.isNotEmpty) const SizedBox(height: 16),

                // Insights
                _SectionCard(
                  title: 'Insights',
                  icon: Icons.lightbulb_outline,
                  child: analytics.insights.isEmpty
                      ? const _EmptyState(
                          message:
                              'Log your steps for a few days to unlock insights.',
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

                // Nudge (if any)
                if (nudge != null) ...[
                  _NudgeCard(nudge: nudge),
                  const SizedBox(height: 16),
                ],

                // Action Button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _logSteps,
                    icon: const Icon(Icons.add),
                    label: const Text('Log Steps'),
                  ),
                ),
                const SizedBox(height: 12),

                // Automatic Tracking Toggle
                _AutomaticTrackingCard(
                  hcService: _hcService,
                  onChanged: _refresh,
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Reusable Widgets
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

class _GoalProgressBar extends StatelessWidget {
  const _GoalProgressBar({
    required this.progress,
    required this.currentSteps,
    required this.goalSteps,
  });

  final int progress;
  final int currentSteps;
  final int goalSteps;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final remaining = (goalSteps - currentSteps).clamp(0, goalSteps);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Goal: ${formatStepsWithComma(goalSteps)} steps',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
          remaining > 0
              ? '${formatStepsWithComma(remaining)} steps remaining'
              : 'Goal achieved! 🎉',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ScoreWidget extends StatelessWidget {
  const _ScoreWidget({
    required this.score,
    required this.label,
    required this.explanation,
  });

  final int score;
  final String label;
  final String explanation;

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
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text('Activity Score', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _TrendWidget extends StatelessWidget {
  const _TrendWidget({required this.direction, required this.description});

  final TrendDirection direction;
  final String description;

  IconData get _icon {
    switch (direction) {
      case TrendDirection.improving:
        return Icons.trending_up;
      case TrendDirection.stable:
        return Icons.trending_flat;
      case TrendDirection.declining:
        return Icons.trending_down;
    }
  }

  Color _color(ColorScheme colorScheme) {
    switch (direction) {
      case TrendDirection.improving:
        return Colors.green;
      case TrendDirection.stable:
        return colorScheme.onSurfaceVariant;
      case TrendDirection.declining:
        return Colors.orange;
    }
  }

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
          Icon(_icon, color: _color(colorScheme), size: 28),
          const SizedBox(height: 4),
          Text(
            direction.name[0].toUpperCase() + direction.name.substring(1),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text('Trend', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
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

class _NudgeCard extends StatelessWidget {
  const _NudgeCard({required this.nudge});

  final ActivityNudge nudge;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.tertiary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.emoji_objects_outlined, color: colorScheme.tertiary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nudge.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    nudge.message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyBarChart extends StatelessWidget {
  const _WeeklyBarChart({required this.records, required this.goal});

  final List<ActivityRecord> records;
  final ActivityGoal goal;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final days = List.generate(7, (i) {
      return DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(Duration(days: 6 - i));
    });

    final maxSteps = days.fold<int>(goal.dailyStepGoal, (max, day) {
      final record = _findRecord(day);
      final steps = record?.steps ?? 0;
      return steps > max ? steps : max;
    });

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: days.map((day) {
          final record = _findRecord(day);
          final steps = record?.steps ?? 0;
          final fraction = maxSteps > 0
              ? (steps / maxSteps).clamp(0.0, 1.0)
              : 0.0;
          final isToday =
              day.day == today.day &&
              day.month == today.month &&
              day.year == today.year;
          final metGoal = steps >= goal.dailyStepGoal;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (steps > 0)
                    Text(
                      formatSteps(steps),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: FractionallySizedBox(
                      heightFactor: fraction.toDouble(),
                      child: Container(
                        decoration: BoxDecoration(
                          color: metGoal
                              ? colorScheme.primary
                              : isToday
                              ? colorScheme.primary.withValues(alpha: 0.6)
                              : colorScheme.primary.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('E').format(day).substring(0, 2),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      color: isToday
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  ActivityRecord? _findRecord(DateTime day) {
    final key = activityDateKey(day);
    for (final r in records) {
      if (r.dateKey == key) return r;
    }
    return null;
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
// Automatic Tracking Card
// =============================================================================

class _AutomaticTrackingCard extends StatefulWidget {
  const _AutomaticTrackingCard({
    required this.hcService,
    required this.onChanged,
  });

  final HealthConnectService hcService;
  final VoidCallback onChanged;

  @override
  State<_AutomaticTrackingCard> createState() => _AutomaticTrackingCardState();
}

class _AutomaticTrackingCardState extends State<_AutomaticTrackingCard> {
  bool _isEnabled = false;
  HealthConnectAvailability _availability =
      HealthConnectAvailability.notApplicable;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final availability = await widget.hcService.checkAvailability();
    if (!mounted) return;
    setState(() {
      _availability = availability;
      _isEnabled = widget.hcService.isEnabled;
      _isLoading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      // Enabling — check permissions first
      final permStatus = await widget.hcService.checkPermissions();
      if (permStatus != HealthPermissionStatus.granted) {
        final result = await widget.hcService.requestPermissions();
        if (result != HealthPermissionStatus.granted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permission required for automatic tracking.'),
            ),
          );
          return;
        }
      }
    }

    await widget.hcService.setEnabled(value);
    setState(() => _isEnabled = value);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    // Don't show on unsupported platforms
    if (_availability == HealthConnectAvailability.notApplicable ||
        _availability == HealthConnectAvailability.unsupportedVersion) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    if (_availability == HealthConnectAvailability.notInstalled) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Automatic Tracking',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Install Health Connect from Play Store to enable automatic step and sleep tracking.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(
              _isEnabled
                  ? Icons.health_and_safety
                  : Icons.health_and_safety_outlined,
              color: _isEnabled ? Colors.green : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Automatic Activity & Sleep Tracking',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _isEnabled
                        ? 'Steps and sleep are tracked automatically.'
                        : 'Enable to import steps and sleep data.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch(value: _isEnabled, onChanged: _toggle),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Log Steps Dialog
// =============================================================================

class _LogStepsDialog extends StatefulWidget {
  const _LogStepsDialog({required this.repository});

  final ActivityRepository repository;

  @override
  State<_LogStepsDialog> createState() => _LogStepsDialogState();
}

class _LogStepsDialogState extends State<_LogStepsDialog> {
  final _controller = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim().replaceAll(',', '');
    final steps = int.tryParse(text);
    if (steps == null || steps <= 0) {
      setState(() => _error = 'Enter a valid step count');
      return;
    }
    if (steps > 200000) {
      setState(() => _error = 'That seems too high');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await widget.repository.upsertRecord(
        date: DateTime.now(),
        steps: steps,
        source: ActivitySource.manual,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log Today\'s Steps'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Steps',
              hintText: 'e.g. 6500',
              errorText: _error,
              border: const OutlineInputBorder(),
              suffixText: 'steps',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'This will set today\'s step count.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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

// =============================================================================
// Goal Settings Dialog
// =============================================================================

class _GoalSettingsDialog extends StatefulWidget {
  const _GoalSettingsDialog({required this.repository});

  final ActivityRepository repository;

  @override
  State<_GoalSettingsDialog> createState() => _GoalSettingsDialogState();
}

class _GoalSettingsDialogState extends State<_GoalSettingsDialog> {
  int _selectedGoal = 8000;
  bool _isCustom = false;
  final _customController = TextEditingController();
  bool _isSaving = false;

  static const _presets = [5000, 8000, 10000];

  @override
  void initState() {
    super.initState();
    _loadCurrentGoal();
  }

  Future<void> _loadCurrentGoal() async {
    final goal = await widget.repository.getGoal();
    if (!mounted) return;
    setState(() {
      _selectedGoal = goal.dailyStepGoal;
      _isCustom = !_presets.contains(goal.dailyStepGoal);
      if (_isCustom) {
        _customController.text = goal.dailyStepGoal.toString();
      }
    });
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    int goalValue = _selectedGoal;
    if (_isCustom) {
      final parsed = int.tryParse(
        _customController.text.trim().replaceAll(',', ''),
      );
      if (parsed == null || parsed < 1000 || parsed > 50000) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a goal between 1,000 and 50,000'),
          ),
        );
        return;
      }
      goalValue = parsed;
    }

    setState(() => _isSaving = true);
    try {
      await widget.repository.saveGoal(ActivityGoal(dailyStepGoal: goalValue));
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
    return AlertDialog(
      title: const Text('Daily Step Goal'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final preset in _presets)
            RadioListTile<int>(
              contentPadding: EdgeInsets.zero,
              title: Text('${formatStepsWithComma(preset)} steps'),
              value: preset,
              groupValue: _isCustom ? -1 : _selectedGoal,
              onChanged: (val) {
                setState(() {
                  _selectedGoal = val!;
                  _isCustom = false;
                });
              },
            ),
          RadioListTile<int>(
            contentPadding: EdgeInsets.zero,
            title: const Text('Custom'),
            value: -1,
            groupValue: _isCustom ? -1 : _selectedGoal,
            onChanged: (_) {
              setState(() => _isCustom = true);
            },
          ),
          if (_isCustom)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 4),
              child: TextField(
                controller: _customController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Custom goal',
                  hintText: 'e.g. 12000',
                  border: OutlineInputBorder(),
                  suffixText: 'steps',
                  isDense: true,
                ),
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
