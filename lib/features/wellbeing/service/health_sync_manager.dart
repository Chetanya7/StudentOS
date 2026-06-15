import 'package:flutter/foundation.dart';

import '../models/activity_models.dart';
import '../models/sleep_models.dart';
import 'activity_repository.dart';
import 'health_connect_service.dart';
import 'sleep_repository.dart';

/// Manages Health Connect synchronization across the app lifecycle.
///
/// Provides:
/// - App-launch sync (called once at startup)
/// - Manual refresh sync (user-triggered pull-to-refresh)
/// - Screen-open sync (when wellbeing screens are opened)
///
/// Key design decisions:
/// - Manual records are NEVER deleted or overwritten.
/// - HC data is stored alongside manual data; HC takes display priority
///   for the same date unless HC returns 0 and manual > 0.
/// - All sync is conditional on user having enabled automatic tracking.
class HealthSyncManager {
  HealthSyncManager._();
  static final HealthSyncManager instance = HealthSyncManager._();

  final HealthConnectService _hcService = HealthConnectService.instance;

  bool _hasPerformedLaunchSync = false;

  /// Whether a sync is currently in progress.
  final ValueNotifier<bool> isSyncing = ValueNotifier(false);

  /// Initialize the manager — call once at app startup.
  Future<void> initialize() async {
    await _hcService.initialize();
  }

  /// Perform app-launch sync (only once per app session).
  Future<void> performLaunchSync({
    required ActivityRepository activityRepository,
    required SleepRepository sleepRepository,
  }) async {
    if (_hasPerformedLaunchSync) return;
    _hasPerformedLaunchSync = true;

    await _performSync(
      activityRepository: activityRepository,
      sleepRepository: sleepRepository,
    );
  }

  /// Perform a manual refresh sync (user-initiated).
  Future<SyncMetadata> performManualSync({
    required ActivityRepository activityRepository,
    required SleepRepository sleepRepository,
  }) async {
    return await _performSync(
      activityRepository: activityRepository,
      sleepRepository: sleepRepository,
    );
  }

  /// Internal sync implementation.
  Future<SyncMetadata> _performSync({
    required ActivityRepository activityRepository,
    required SleepRepository sleepRepository,
  }) async {
    if (!_hcService.isEnabled) return SyncMetadata.initial;

    isSyncing.value = true;
    try {
      final metadata = await _hcService.performSync(
        onStepsData: (records) => _mergeStepRecords(
          activityRepository: activityRepository,
          hcRecords: records,
        ),
        onSleepData: (records) => _mergeSleepRecords(
          sleepRepository: sleepRepository,
          hcRecords: records,
        ),
      );
      return metadata;
    } finally {
      isSyncing.value = false;
    }
  }

  /// Merge HC step records into the activity repository.
  /// Manual records are preserved — HC data is stored separately.
  Future<void> _mergeStepRecords({
    required ActivityRepository activityRepository,
    required List<ActivityRecord> hcRecords,
  }) async {
    for (final hcRecord in hcRecords) {
      // Get existing record for this date
      final existing = await activityRepository.getRecordForDate(hcRecord.date);

      if (existing == null) {
        // No existing record — insert HC data
        await activityRepository.upsertRecord(
          date: hcRecord.date,
          steps: hcRecord.steps,
          source: ActivitySource.healthConnect,
        );
      } else if (existing.source == ActivitySource.healthConnect) {
        // Update existing HC record with latest data
        await activityRepository.upsertRecord(
          date: hcRecord.date,
          steps: hcRecord.steps,
          source: ActivitySource.healthConnect,
        );
      } else if (existing.source == ActivitySource.manual) {
        // Manual record exists — HC takes priority UNLESS HC is 0 and manual > 0
        if (hcRecord.steps > 0) {
          await activityRepository.upsertRecord(
            date: hcRecord.date,
            steps: hcRecord.steps,
            source: ActivitySource.healthConnect,
          );
        }
        // If HC returns 0 and manual > 0, keep manual (don't overwrite)
      }
    }
  }

  /// Merge HC sleep records into the sleep repository.
  /// Manual records are preserved — HC data only fills gaps or updates HC records.
  Future<void> _mergeSleepRecords({
    required SleepRepository sleepRepository,
    required List<SleepRecord> hcRecords,
  }) async {
    for (final hcRecord in hcRecords) {
      final existing = await sleepRepository.getRecordForDate(hcRecord.date);

      if (existing == null) {
        // No existing record — insert HC data
        await sleepRepository.upsertRecord(
          date: hcRecord.date,
          sleepTime: hcRecord.sleepTime,
          wakeTime: hcRecord.wakeTime,
          source: SleepSource.healthConnect,
        );
      } else if (existing.source == SleepSource.healthConnect) {
        // Update existing HC record
        await sleepRepository.upsertRecord(
          date: hcRecord.date,
          sleepTime: hcRecord.sleepTime,
          wakeTime: hcRecord.wakeTime,
          source: SleepSource.healthConnect,
        );
      }
      // If manual record exists, DO NOT overwrite — preserve user's manual entry.
    }
  }
}
