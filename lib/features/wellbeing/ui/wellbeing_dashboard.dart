import 'package:flutter/material.dart';

import '../../notification_reading/service/notification_service.dart';
import '../models/activity_models.dart';
import '../models/hydration_models.dart';
import '../models/sleep_models.dart';
import '../service/activity_repository.dart';
import '../service/health_sync_manager.dart';
import '../service/hydration_service.dart';
import '../service/sleep_repository.dart';
import '../service/wellbeing_service.dart';
import 'activity_details_screen.dart';
import 'breathwork_session.dart';
import 'hydration_details_screen.dart';
import 'sleep_details_screen.dart';
import 'wellbeing_prompt_screen.dart';

class WellbeingDashboard extends StatefulWidget {
  const WellbeingDashboard({super.key, required this.notificationService});

  final NotificationService notificationService;

  @override
  State<WellbeingDashboard> createState() => _WellbeingDashboardState();
}

class _WellbeingDashboardState extends State<WellbeingDashboard> {
  late final HydrationService _hydrationService;
  late final SleepRepository _sleepRepository;
  late final ActivityRepository _activityRepository;
  late Future<_DashboardSnapshot> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _hydrationService = HydrationService(
      notificationService: widget.notificationService,
    );
    _sleepRepository = SleepRepository();
    _activityRepository = ActivityRepository();
    _performLaunchSyncAndLoad();
  }

  Future<void> _performLaunchSyncAndLoad() async {
    // Perform app-launch sync (no-op if already done this session).
    await HealthSyncManager.instance.performLaunchSync(
      activityRepository: _activityRepository,
      sleepRepository: _sleepRepository,
    );
    _loadSnapshot();
  }

  void _loadSnapshot() {
    _snapshotFuture = _fetchSnapshot();
    if (mounted) setState(() {});
  }

  Future<_DashboardSnapshot> _fetchSnapshot() async {
    final results = await Future.wait([
      _hydrationService.getSummary(),
      _sleepRepository.getDashboardData(),
      _activityRepository.getDashboardData(),
    ]);
    return _DashboardSnapshot(
      hydration: results[0] as HydrationSummary,
      sleep: results[1] as SleepDashboardData,
      activity: results[2] as ActivityDashboardData,
    );
  }

  void _refresh() {
    setState(() {
      _snapshotFuture = _syncAndFetchSnapshot();
    });
  }

  Future<_DashboardSnapshot> _syncAndFetchSnapshot() async {
    // Perform manual refresh sync.
    await HealthSyncManager.instance.performManualSync(
      activityRepository: _activityRepository,
      sleepRepository: _sleepRepository,
    );
    return _fetchSnapshot();
  }

  Future<void> _addWater() async {
    await _hydrationService.addWater();
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Logged 250 ml. Keep it up!')));
  }

  Future<void> _logSleep() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _QuickSleepLogDialog(repository: _sleepRepository),
    );
    if (saved == true && mounted) {
      _refresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sleep record saved.')));
    }
  }

  void _openMoodCheckIn() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            WellbeingPromptScreen(wellbeingService: WellbeingService()),
      ),
    ).then((_) {
      if (mounted) _refresh();
    });
  }

  void _openBreathwork() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BreathworkSession()),
    );
  }

  void _openSleepDetails(SleepDashboardData data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SleepDetailsScreen(repository: _sleepRepository, initialData: data),
      ),
    ).then((_) {
      if (mounted) _refresh();
    });
  }

  void _openHydrationDetails(HydrationSummary summary) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HydrationDetailsScreen(
          hydrationService: _hydrationService,
          initialSummary: summary,
        ),
      ),
    ).then((_) {
      if (mounted) _refresh();
    });
  }

  void _openActivityDetails(ActivityDashboardData data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityDetailsScreen(
          repository: _activityRepository,
          initialData: data,
        ),
      ),
    ).then((_) {
      if (mounted) _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_DashboardSnapshot>(
        future: _snapshotFuture,
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
                  Text(
                    'Could not load wellbeing data\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            );
          }

          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Wellbeing',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                // Section 1: Today's Wellness Snapshot
                _WellnessSnapshotCard(
                  sleep: data.sleep,
                  hydration: data.hydration,
                  activity: data.activity,
                ),
                const SizedBox(height: 24),
                // Section 2: Quick Actions
                _QuickActionsGrid(
                  onLogWater: _addWater,
                  onLogSleep: _logSleep,
                  onMoodCheckIn: _openMoodCheckIn,
                  onBreathwork: _openBreathwork,
                ),
                const SizedBox(height: 24),
                // Section 3: Health Summaries
                _ActivitySummaryCard(
                  data: data.activity,
                  onViewDetails: () => _openActivityDetails(data.activity),
                ),
                const SizedBox(height: 16),
                _SleepSummaryCard(
                  data: data.sleep,
                  onViewDetails: () => _openSleepDetails(data.sleep),
                ),
                const SizedBox(height: 16),
                _HydrationSummaryCard(
                  summary: data.hydration,
                  onViewDetails: () => _openHydrationDetails(data.hydration),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DashboardSnapshot {
  const _DashboardSnapshot({
    required this.hydration,
    required this.sleep,
    required this.activity,
  });

  final HydrationSummary hydration;
  final SleepDashboardData sleep;
  final ActivityDashboardData activity;
}

// =============================================================================
// Section 1: Today's Wellness Snapshot Hero Card
// =============================================================================

class _WellnessSnapshotCard extends StatelessWidget {
  const _WellnessSnapshotCard({
    required this.sleep,
    required this.hydration,
    required this.activity,
  });

  final SleepDashboardData sleep;
  final HydrationSummary hydration;
  final ActivityDashboardData activity;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lastNight = sleep.lastNight;
    final sleepText = lastNight != null
        ? formatSleepDuration(lastNight.durationMinutes)
        : 'No data';
    final goalMlLiters = hydration.today.goalMl / 1000;
    final currentLiters = hydration.today.amountMl / 1000;
    final hydrationText =
        '${currentLiters.toStringAsFixed(1)} / ${goalMlLiters.toStringAsFixed(1)} L';
    final activityText = '${formatStepsWithComma(activity.todaySteps)} steps';

    // Overall wellness score (simple average of sleep goal % + hydration % + activity %)
    final sleepGoalProgress = lastNight == null
        ? 0.0
        : (lastNight.durationMinutes / sleep.settings.sleepGoalMinutes)
              .clamp(0, 1)
              .toDouble();
    final hydrationProgress = hydration.progress;
    final activityProgress = activity.goalProgress;
    final overallScore =
        ((sleepGoalProgress + hydrationProgress + activityProgress) / 3 * 100)
            .round();

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.favorite, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  "Today's Wellness",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SnapshotMetric(
                    emoji: '😴',
                    label: 'Sleep',
                    value: sleepText,
                  ),
                ),
                Expanded(
                  child: _SnapshotMetric(
                    emoji: '💧',
                    label: 'Water',
                    value: hydrationText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SnapshotMetric(
                    emoji: '🚶',
                    label: 'Activity',
                    value: activityText,
                  ),
                ),
                Expanded(
                  child: _SnapshotMetric(
                    emoji: '✨',
                    label: 'Overall',
                    value: '$overallScore / 100',
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

class _SnapshotMetric extends StatelessWidget {
  const _SnapshotMetric({
    required this.emoji,
    required this.label,
    required this.value,
  });

  final String emoji;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
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
// Section 2: Quick Actions Grid (2x2)
// =============================================================================

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({
    required this.onLogWater,
    required this.onLogSleep,
    required this.onMoodCheckIn,
    required this.onBreathwork,
  });

  final VoidCallback onLogWater;
  final VoidCallback onLogSleep;
  final VoidCallback onMoodCheckIn;
  final VoidCallback onBreathwork;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.water_drop_outlined,
                label: 'Log Water',
                onTap: onLogWater,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionTile(
                icon: Icons.bedtime_outlined,
                label: 'Log Sleep',
                onTap: onLogSleep,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.mood_outlined,
                label: 'Mood Check-In',
                onTap: onMoodCheckIn,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionTile(
                icon: Icons.self_improvement,
                label: 'Breathing',
                onTap: onBreathwork,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: colorScheme.primary),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Section 3: Activity Summary Card
// =============================================================================

class _ActivitySummaryCard extends StatelessWidget {
  const _ActivitySummaryCard({required this.data, required this.onViewDetails});

  final ActivityDashboardData data;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stepsText = formatStepsWithComma(data.todaySteps);
    final scoreText = data.analytics.activityScore;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onViewDetails,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: data.goalProgress,
                      strokeWidth: 4,
                      backgroundColor: Colors.green.withValues(alpha: 0.1),
                      color: Colors.green,
                    ),
                    const Center(
                      child: Icon(
                        Icons.directions_walk,
                        size: 18,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Activity & Movement',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$stepsText steps today',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      data.todaySteps > 0
                          ? '${data.goalPercentage}% of goal • Score: $scoreText/100'
                          : 'Log your steps to get started',
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
// Section 3: Sleep Summary Card
// =============================================================================

class _SleepSummaryCard extends StatelessWidget {
  const _SleepSummaryCard({required this.data, required this.onViewDetails});

  final SleepDashboardData data;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final lastNight = data.lastNight;
    final goalProgress = lastNight == null
        ? 0
        : ((lastNight.durationMinutes / data.settings.sleepGoalMinutes) * 100)
              .round()
              .clamp(0, 100);
    final durationText = lastNight != null
        ? formatSleepDuration(lastNight.durationMinutes)
        : 'No data';
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onViewDetails,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.indigo.withValues(alpha: 0.1),
                child: const Icon(Icons.bedtime_outlined, color: Colors.indigo),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sleep',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$durationText last night',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      lastNight != null
                          ? 'Goal: $goalProgress% • Score: ${data.analytics.sleepScore}/100'
                          : 'Log your first night',
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
// Section 3: Hydration Summary Card
// =============================================================================

class _HydrationSummaryCard extends StatelessWidget {
  const _HydrationSummaryCard({
    required this.summary,
    required this.onViewDetails,
  });

  final HydrationSummary summary;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentLiters = summary.today.amountMl / 1000;
    final goalLiters = summary.today.goalMl / 1000;
    final progressText =
        '${currentLiters.toStringAsFixed(1)}L / ${goalLiters.toStringAsFixed(1)}L';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onViewDetails,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: summary.progress,
                      strokeWidth: 4,
                      backgroundColor: colorScheme.primary.withValues(
                        alpha: 0.1,
                      ),
                      color: colorScheme.primary,
                    ),
                    Center(
                      child: Icon(
                        Icons.water_drop,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hydration',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      progressText,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      '${summary.percentComplete}% complete',
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
// Quick Sleep Log Dialog
// =============================================================================

class _QuickSleepLogDialog extends StatefulWidget {
  const _QuickSleepLogDialog({required this.repository});

  final SleepRepository repository;

  @override
  State<_QuickSleepLogDialog> createState() => _QuickSleepLogDialogState();
}

class _QuickSleepLogDialogState extends State<_QuickSleepLogDialog> {
  late TimeOfDay _sleepTime;
  late TimeOfDay _wakeTime;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _sleepTime = const TimeOfDay(hour: 23, minute: 0);
    _wakeTime = const TimeOfDay(hour: 7, minute: 0);
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
        date: DateTime.now(),
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
      title: const Text('Log last night\'s sleep'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Bedtime'),
            trailing: Text(_sleepTime.format(context)),
            onTap: _pickSleepTime,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('Wake time'),
            trailing: Text(_wakeTime.format(context)),
            onTap: _pickWakeTime,
          ),
          const SizedBox(height: 12),
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
