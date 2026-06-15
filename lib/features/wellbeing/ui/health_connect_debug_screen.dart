import 'package:flutter/material.dart';

import '../models/activity_models.dart';
import '../models/sleep_models.dart';
import '../service/activity_repository.dart';
import '../service/health_connect_service.dart';
import '../service/health_sync_manager.dart';
import '../service/sleep_repository.dart';

/// Debug-only screen showing Health Connect integration status.
///
/// This screen should only be accessible in debug/profile builds.
/// It shows:
/// - Health Connect availability
/// - Permission status
/// - Last sync timestamp and status
/// - Imported data counts
/// - Current data source for today's data
class HealthConnectDebugScreen extends StatefulWidget {
  const HealthConnectDebugScreen({super.key});

  @override
  State<HealthConnectDebugScreen> createState() =>
      _HealthConnectDebugScreenState();
}

class _HealthConnectDebugScreenState extends State<HealthConnectDebugScreen> {
  final _hcService = HealthConnectService.instance;
  final _syncManager = HealthSyncManager.instance;
  final _activityRepo = ActivityRepository();
  final _sleepRepo = SleepRepository();

  bool _isLoading = true;
  bool _isSyncing = false;

  // Status data
  HealthConnectAvailability _availability =
      HealthConnectAvailability.notApplicable;
  HealthPermissionStatus _permissionStatus =
      HealthPermissionStatus.notDetermined;
  SyncMetadata _syncMetadata = SyncMetadata.initial;
  bool _isEnabled = false;

  // Current data
  ActivityRecord? _todayActivity;
  SleepRecord? _lastSleep;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);

    try {
      final availability = await _hcService.checkAvailability();
      final permStatus = await _hcService.checkPermissions();
      final metadata = await _hcService.getSyncMetadata();
      final isEnabled = _hcService.isEnabled;
      final todayRecord = await _activityRepo.getRecordForDate(DateTime.now());
      final sleepRecords = await _sleepRepo.getRecords();

      if (!mounted) return;
      setState(() {
        _availability = availability;
        _permissionStatus = permStatus;
        _syncMetadata = metadata;
        _isEnabled = isEnabled;
        _todayActivity = todayRecord;
        _lastSleep = sleepRecords.isNotEmpty ? sleepRecords.first : null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _triggerSync() async {
    setState(() => _isSyncing = true);
    try {
      await _syncManager.performManualSync(
        activityRepository: _activityRepo,
        sleepRepository: _sleepRepo,
      );
      await _loadStatus();
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _requestPermissions() async {
    final result = await _hcService.requestPermissions();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Permission result: ${result.name}')),
    );
    await _loadStatus();
  }

  Future<void> _toggleEnabled() async {
    await _hcService.setEnabled(!_isEnabled);
    await _loadStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Data (Debug)'),
        actions: [
          IconButton(onPressed: _loadStatus, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Debug banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bug_report, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Debug-only screen. Not visible in release builds.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Health Connect Status
                _SectionHeader(title: 'Health Connect Status'),
                _StatusRow(
                  label: 'Availability',
                  value: _availabilityText,
                  valueColor: _availabilityColor,
                ),
                _StatusRow(
                  label: 'Permissions',
                  value: _permissionText,
                  valueColor: _permissionColor,
                ),
                _StatusRow(
                  label: 'Automatic Tracking',
                  value: _isEnabled ? 'Enabled' : 'Disabled',
                  valueColor: _isEnabled ? Colors.green : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _toggleEnabled,
                        child: Text(_isEnabled ? 'Disable' : 'Enable'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _availability == HealthConnectAvailability.available
                            ? _requestPermissions
                            : null,
                        child: const Text('Request Permissions'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Sync Status
                _SectionHeader(title: 'Last Sync'),
                _StatusRow(
                  label: 'Time',
                  value: _syncMetadata.lastSyncTime != null
                      ? _formatDateTime(_syncMetadata.lastSyncTime!)
                      : 'Never',
                ),
                _StatusRow(
                  label: 'Status',
                  value: _syncStatusText,
                  valueColor: _syncStatusColor,
                ),
                _StatusRow(
                  label: 'Steps Records Imported',
                  value: '${_syncMetadata.stepsImported}',
                ),
                _StatusRow(
                  label: 'Sleep Records Imported',
                  value: '${_syncMetadata.sleepRecordsImported}',
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _isSyncing ? null : _triggerSync,
                  icon: _isSyncing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_isSyncing ? 'Syncing...' : 'Trigger Sync Now'),
                ),
                const SizedBox(height: 24),

                // Imported Data
                _SectionHeader(title: 'Current Data'),
                _StatusRow(
                  label: "Today's Steps",
                  value: _todayActivity != null
                      ? '${formatStepsWithComma(_todayActivity!.steps)} steps'
                      : 'No data',
                ),
                _StatusRow(
                  label: "Today's Activity Source",
                  value: _todayActivity?.source.name ?? 'N/A',
                  valueColor: _sourceColor(_todayActivity?.source),
                ),
                const Divider(height: 16),
                _StatusRow(
                  label: 'Latest Sleep',
                  value: _lastSleep != null
                      ? '${formatSleepDuration(_lastSleep!.durationMinutes)} (${_lastSleep!.dateKey})'
                      : 'No data',
                ),
                _StatusRow(
                  label: 'Sleep Source',
                  value: _lastSleep?.source.name ?? 'N/A',
                  valueColor: _sleepSourceColor(_lastSleep?.source),
                ),
                const SizedBox(height: 24),

                // Active Data Source Summary
                _SectionHeader(title: 'Active Data Source'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _activeDataSourceDescription,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
    );
  }

  // ===========================================================================
  // Computed display values
  // ===========================================================================

  String get _availabilityText {
    switch (_availability) {
      case HealthConnectAvailability.available:
        return 'Installed';
      case HealthConnectAvailability.notInstalled:
        return 'Not Installed';
      case HealthConnectAvailability.unsupportedVersion:
        return 'Unsupported Android Version';
      case HealthConnectAvailability.notApplicable:
        return 'Not Applicable (non-Android)';
    }
  }

  Color? get _availabilityColor {
    switch (_availability) {
      case HealthConnectAvailability.available:
        return Colors.green;
      case HealthConnectAvailability.notInstalled:
        return Colors.orange;
      case HealthConnectAvailability.unsupportedVersion:
        return Colors.red;
      case HealthConnectAvailability.notApplicable:
        return null;
    }
  }

  String get _permissionText {
    switch (_permissionStatus) {
      case HealthPermissionStatus.granted:
        return 'Granted';
      case HealthPermissionStatus.denied:
        return 'Denied';
      case HealthPermissionStatus.notDetermined:
        return 'Not Determined';
    }
  }

  Color? get _permissionColor {
    switch (_permissionStatus) {
      case HealthPermissionStatus.granted:
        return Colors.green;
      case HealthPermissionStatus.denied:
        return Colors.red;
      case HealthPermissionStatus.notDetermined:
        return Colors.orange;
    }
  }

  String get _syncStatusText {
    switch (_syncMetadata.lastSyncStatus) {
      case SyncStatus.success:
        return 'Success';
      case SyncStatus.failed:
        return 'Failed';
      case SyncStatus.neverSynced:
        return 'Never Synced';
      case SyncStatus.permissionDenied:
        return 'Permission Denied';
    }
  }

  Color? get _syncStatusColor {
    switch (_syncMetadata.lastSyncStatus) {
      case SyncStatus.success:
        return Colors.green;
      case SyncStatus.failed:
        return Colors.red;
      case SyncStatus.neverSynced:
        return null;
      case SyncStatus.permissionDenied:
        return Colors.orange;
    }
  }

  Color? _sourceColor(ActivitySource? source) {
    if (source == null) return null;
    switch (source) {
      case ActivitySource.healthConnect:
        return Colors.green;
      case ActivitySource.manual:
        return Colors.blue;
      default:
        return Colors.purple;
    }
  }

  Color? _sleepSourceColor(SleepSource? source) {
    if (source == null) return null;
    switch (source) {
      case SleepSource.healthConnect:
        return Colors.green;
      case SleepSource.manual:
        return Colors.blue;
      default:
        return Colors.purple;
    }
  }

  String get _activeDataSourceDescription {
    if (_isEnabled &&
        _availability == HealthConnectAvailability.available &&
        _permissionStatus == HealthPermissionStatus.granted) {
      return 'Health Connect (automatic tracking active). '
          'Manual entries are preserved alongside automatic data.';
    }
    if (_isEnabled &&
        _availability == HealthConnectAvailability.available &&
        _permissionStatus != HealthPermissionStatus.granted) {
      return 'Automatic tracking enabled but permissions not granted. '
          'Falling back to manual entry only.';
    }
    if (_availability != HealthConnectAvailability.available) {
      return 'Health Connect is not available on this device. '
          'Using manual entry only.';
    }
    return 'Automatic tracking is disabled. Using manual entry only.';
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// =============================================================================
// Widgets
// =============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
