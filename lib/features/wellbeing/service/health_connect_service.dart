import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/activity_models.dart';
import '../models/sleep_models.dart';

// =============================================================================
// Sync Metadata
// =============================================================================

/// Status of the last sync attempt.
enum SyncStatus { success, failed, neverSynced, permissionDenied }

/// Metadata about the most recent Health Connect sync.
class SyncMetadata {
  const SyncMetadata({
    required this.lastSyncTime,
    required this.lastSyncStatus,
    required this.stepsImported,
    required this.sleepRecordsImported,
  });

  final DateTime? lastSyncTime;
  final SyncStatus lastSyncStatus;
  final int stepsImported;
  final int sleepRecordsImported;

  static const initial = SyncMetadata(
    lastSyncTime: null,
    lastSyncStatus: SyncStatus.neverSynced,
    stepsImported: 0,
    sleepRecordsImported: 0,
  );

  Map<String, dynamic> toJson() => {
    'lastSyncTime': lastSyncTime?.toIso8601String(),
    'lastSyncStatus': lastSyncStatus.name,
    'stepsImported': stepsImported,
    'sleepRecordsImported': sleepRecordsImported,
  };

  factory SyncMetadata.fromJson(Map<String, dynamic> json) {
    return SyncMetadata(
      lastSyncTime: json['lastSyncTime'] != null
          ? DateTime.tryParse(json['lastSyncTime'].toString())
          : null,
      lastSyncStatus: _parseSyncStatus(json['lastSyncStatus']),
      stepsImported: (json['stepsImported'] as int?) ?? 0,
      sleepRecordsImported: (json['sleepRecordsImported'] as int?) ?? 0,
    );
  }
}

SyncStatus _parseSyncStatus(Object? value) {
  final name = value?.toString() ?? '';
  for (final s in SyncStatus.values) {
    if (s.name == name) return s;
  }
  return SyncStatus.neverSynced;
}

// =============================================================================
// Health Connect Availability
// =============================================================================

/// Whether Health Connect can be used on this device.
enum HealthConnectAvailability {
  /// Device is not Android — HC not applicable.
  notApplicable,

  /// Android version too low (< API 26).
  unsupportedVersion,

  /// Health Connect is not installed.
  notInstalled,

  /// Health Connect is available and can be used.
  available,
}

/// Permission state for Health Connect data types.
enum HealthPermissionStatus { granted, denied, notDetermined }

// =============================================================================
// Health Connect Service
// =============================================================================

/// Service for integrating with Android Health Connect.
///
/// This service conditionally enables HC only on supported Android devices
/// (API 26+). On devices below API 26 or non-Android platforms, all methods
/// gracefully return indicating HC is unavailable.
///
/// The service uses the `health` Flutter package under the hood but wraps it
/// to provide a clean interface tailored to StudentOS needs.
class HealthConnectService {
  HealthConnectService._();
  static final HealthConnectService instance = HealthConnectService._();

  static const _platform = MethodChannel('studentos/health_connect');
  static const _metadataKey = 'health_connect_sync_metadata';
  static const _enabledKey = 'health_connect_enabled';

  /// Cached availability after first check.
  HealthConnectAvailability? _cachedAvailability;

  /// Whether automatic tracking is enabled by the user.
  final ValueNotifier<bool> enabledNotifier = ValueNotifier(false);

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initialize — loads user preference for automatic tracking.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    enabledNotifier.value = prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    enabledNotifier.value = enabled;
  }

  bool get isEnabled => enabledNotifier.value;

  // ---------------------------------------------------------------------------
  // Availability
  // ---------------------------------------------------------------------------

  /// Checks Health Connect availability.
  /// Returns immediately on non-Android or low API levels.
  Future<HealthConnectAvailability> checkAvailability() async {
    if (_cachedAvailability != null) return _cachedAvailability!;

    // Only Android supports Health Connect.
    if (!Platform.isAndroid) {
      _cachedAvailability = HealthConnectAvailability.notApplicable;
      return _cachedAvailability!;
    }

    try {
      final result = await _platform.invokeMethod<Map>('checkAvailability');
      final status = result?['status']?.toString() ?? 'unavailable';

      switch (status) {
        case 'available':
          _cachedAvailability = HealthConnectAvailability.available;
        case 'unsupportedVersion':
          _cachedAvailability = HealthConnectAvailability.unsupportedVersion;
        case 'notInstalled':
          _cachedAvailability = HealthConnectAvailability.notInstalled;
        default:
          _cachedAvailability = HealthConnectAvailability.notInstalled;
      }
    } on PlatformException catch (_) {
      _cachedAvailability = HealthConnectAvailability.notInstalled;
    } on MissingPluginException catch (_) {
      // Platform channel not registered — HC not available in this build.
      _cachedAvailability = HealthConnectAvailability.notApplicable;
    }

    return _cachedAvailability!;
  }

  /// Whether HC is available on this device.
  Future<bool> get isAvailable async {
    final status = await checkAvailability();
    return status == HealthConnectAvailability.available;
  }

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  /// Checks if required permissions are granted.
  Future<HealthPermissionStatus> checkPermissions() async {
    if (!await isAvailable) return HealthPermissionStatus.denied;

    try {
      final result = await _platform.invokeMethod<Map>('checkPermissions');
      final granted = result?['granted'] as bool? ?? false;
      return granted
          ? HealthPermissionStatus.granted
          : HealthPermissionStatus.denied;
    } on PlatformException catch (_) {
      return HealthPermissionStatus.denied;
    } on MissingPluginException catch (_) {
      return HealthPermissionStatus.denied;
    }
  }

  /// Requests Health Connect permissions from the user.
  Future<HealthPermissionStatus> requestPermissions() async {
    if (!await isAvailable) return HealthPermissionStatus.denied;

    try {
      final result = await _platform.invokeMethod<Map>('requestPermissions');
      final granted = result?['granted'] as bool? ?? false;
      return granted
          ? HealthPermissionStatus.granted
          : HealthPermissionStatus.denied;
    } on PlatformException catch (_) {
      return HealthPermissionStatus.denied;
    } on MissingPluginException catch (_) {
      return HealthPermissionStatus.denied;
    }
  }

  // ---------------------------------------------------------------------------
  // Data Reading
  // ---------------------------------------------------------------------------

  /// Fetches step count data for a date range.
  /// Returns a list of ActivityRecords sourced from Health Connect.
  Future<List<ActivityRecord>> fetchSteps({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!await isAvailable) return [];

    try {
      final result = await _platform.invokeMethod<List>('getSteps', {
        'startTime': start.millisecondsSinceEpoch,
        'endTime': end.millisecondsSinceEpoch,
      });

      if (result == null) return [];

      final records = <ActivityRecord>[];
      for (final item in result) {
        if (item is Map) {
          final dateMs = item['date'] as int?;
          final steps = item['steps'] as int? ?? 0;
          if (dateMs != null && steps > 0) {
            final date = DateTime.fromMillisecondsSinceEpoch(dateMs);
            final normalizedDate = DateTime(date.year, date.month, date.day);
            records.add(
              ActivityRecord(
                id: '${activityDateKey(normalizedDate)}_hc',
                date: normalizedDate,
                steps: steps,
                source: ActivitySource.healthConnect,
              ),
            );
          }
        }
      }
      return records;
    } on PlatformException catch (_) {
      return [];
    } on MissingPluginException catch (_) {
      return [];
    }
  }

  /// Fetches sleep sessions for a date range.
  /// Returns a list of SleepRecords sourced from Health Connect.
  Future<List<SleepRecord>> fetchSleepSessions({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!await isAvailable) return [];

    try {
      final result = await _platform.invokeMethod<List>('getSleepSessions', {
        'startTime': start.millisecondsSinceEpoch,
        'endTime': end.millisecondsSinceEpoch,
      });

      if (result == null) return [];

      final records = <SleepRecord>[];
      for (final item in result) {
        if (item is Map) {
          final startMs = item['startTime'] as int?;
          final endMs = item['endTime'] as int?;
          if (startMs != null && endMs != null) {
            final sleepStart = DateTime.fromMillisecondsSinceEpoch(startMs);
            final sleepEnd = DateTime.fromMillisecondsSinceEpoch(endMs);
            final date = DateTime(sleepEnd.year, sleepEnd.month, sleepEnd.day);
            final sleepMinutes = sleepStart.hour * 60 + sleepStart.minute;
            final wakeMinutes = sleepEnd.hour * 60 + sleepEnd.minute;
            final duration = sleepEnd.difference(sleepStart).inMinutes.abs();

            records.add(
              SleepRecord(
                id: '${sleepDateKey(date)}_hc',
                date: date,
                sleepTime: sleepMinutes,
                wakeTime: wakeMinutes,
                durationMinutes: duration,
                source: SleepSource.healthConnect,
              ),
            );
          }
        }
      }
      return records;
    } on PlatformException catch (_) {
      return [];
    } on MissingPluginException catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------------

  /// Performs a full sync: fetches steps (30 days) and sleep (7 days).
  /// Returns updated sync metadata.
  Future<SyncMetadata> performSync({
    required Future<void> Function(List<ActivityRecord> records) onStepsData,
    required Future<void> Function(List<SleepRecord> records) onSleepData,
  }) async {
    if (!isEnabled) {
      return SyncMetadata.initial;
    }

    final availability = await checkAvailability();
    if (availability != HealthConnectAvailability.available) {
      return await _saveSyncMetadata(
        SyncMetadata(
          lastSyncTime: DateTime.now(),
          lastSyncStatus: SyncStatus.failed,
          stepsImported: 0,
          sleepRecordsImported: 0,
        ),
      );
    }

    final permStatus = await checkPermissions();
    if (permStatus != HealthPermissionStatus.granted) {
      return await _saveSyncMetadata(
        SyncMetadata(
          lastSyncTime: DateTime.now(),
          lastSyncStatus: SyncStatus.permissionDenied,
          stepsImported: 0,
          sleepRecordsImported: 0,
        ),
      );
    }

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final thirtyDaysAgo = today.subtract(const Duration(days: 30));
      final sevenDaysAgo = today.subtract(const Duration(days: 7));
      final endOfDay = today.add(const Duration(days: 1));

      // Fetch steps (30-day history)
      final stepRecords = await fetchSteps(start: thirtyDaysAgo, end: endOfDay);

      // Fetch sleep (7-day history)
      final sleepRecords = await fetchSleepSessions(
        start: sevenDaysAgo,
        end: endOfDay,
      );

      // Deliver data to repositories
      if (stepRecords.isNotEmpty) await onStepsData(stepRecords);
      if (sleepRecords.isNotEmpty) await onSleepData(sleepRecords);

      final metadata = SyncMetadata(
        lastSyncTime: DateTime.now(),
        lastSyncStatus: SyncStatus.success,
        stepsImported: stepRecords.length,
        sleepRecordsImported: sleepRecords.length,
      );

      return await _saveSyncMetadata(metadata);
    } catch (e) {
      debugPrint('Health Connect sync failed: $e');
      return await _saveSyncMetadata(
        SyncMetadata(
          lastSyncTime: DateTime.now(),
          lastSyncStatus: SyncStatus.failed,
          stepsImported: 0,
          sleepRecordsImported: 0,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Sync Metadata Persistence
  // ---------------------------------------------------------------------------

  Future<SyncMetadata> getSyncMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_metadataKey);
    if (source == null || source.isEmpty) return SyncMetadata.initial;

    try {
      final decoded = jsonDecode(source);
      if (decoded is Map) {
        return SyncMetadata.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
    return SyncMetadata.initial;
  }

  Future<SyncMetadata> _saveSyncMetadata(SyncMetadata metadata) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_metadataKey, jsonEncode(metadata.toJson()));
    return metadata;
  }
}
