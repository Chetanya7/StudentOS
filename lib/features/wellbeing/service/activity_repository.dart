import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/activity_models.dart';
import 'activity_analytics_service.dart';

/// Repository for persisting and retrieving activity records and goals.
///
/// Uses SharedPreferences to match the existing project storage pattern.
/// Designed to be offline-first and easily extensible for future health
/// platform integrations (Health Connect, HealthKit).
class ActivityRepository {
  ActivityRepository({ActivityAnalyticsService? analyticsService})
    : _analyticsService = analyticsService ?? const ActivityAnalyticsService();

  static const _goalKey = 'activity_goal_json';
  static const _recordsKey = 'activity_records_json';

  final ActivityAnalyticsService _analyticsService;

  /// Notifies listeners when data changes (for UI refresh patterns).
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  // ---------------------------------------------------------------------------
  // Goal
  // ---------------------------------------------------------------------------

  Future<ActivityGoal> getGoal() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_goalKey);
    if (source == null || source.isEmpty) return ActivityGoal.defaults;

    try {
      final decoded = jsonDecode(source);
      if (decoded is Map) {
        return ActivityGoal.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {
      // Gracefully fall back to defaults on corrupt data.
    }

    return ActivityGoal.defaults;
  }

  Future<void> saveGoal(ActivityGoal goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_goalKey, jsonEncode(goal.toJson()));
    changes.value++;
  }

  // ---------------------------------------------------------------------------
  // Records
  // ---------------------------------------------------------------------------

  Future<List<ActivityRecord>> getRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_recordsKey);
    if (source == null || source.isEmpty) return <ActivityRecord>[];

    try {
      final decoded = jsonDecode(source);
      if (decoded is List) {
        final records =
            decoded
                .whereType<Map>()
                .map(
                  (item) =>
                      ActivityRecord.fromJson(item.cast<String, dynamic>()),
                )
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date));
        return records;
      }
    } catch (_) {
      // Keep app usable when stored data is malformed.
    }

    return <ActivityRecord>[];
  }

  Future<ActivityRecord?> getRecordForDate(DateTime date) async {
    final key = activityDateKey(date);
    final records = await getRecords();
    for (final record in records) {
      if (record.dateKey == key) return record;
    }
    return null;
  }

  /// Upserts an activity record for the given date.
  /// If [addToExisting] is true, adds steps to any existing record for that date.
  Future<ActivityRecord> upsertRecord({
    required DateTime date,
    required int steps,
    ActivitySource source = ActivitySource.manual,
    bool addToExisting = false,
  }) async {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final key = activityDateKey(normalizedDate);

    final records = await getRecords();
    final existingIndex = records.indexWhere((r) => r.dateKey == key);

    final int finalSteps;
    if (addToExisting && existingIndex != -1) {
      finalSteps = records[existingIndex].steps + steps;
    } else {
      finalSteps = steps;
    }

    final record = ActivityRecord(
      id: key,
      date: normalizedDate,
      steps: finalSteps.clamp(0, 200000),
      source: source,
    );

    if (existingIndex == -1) {
      records.add(record);
    } else {
      records[existingIndex] = record;
    }

    await _saveRecords(records);
    changes.value++;
    return record;
  }

  // ---------------------------------------------------------------------------
  // Dashboard Data
  // ---------------------------------------------------------------------------

  Future<ActivityDashboardData> getDashboardData() async {
    final goal = await getGoal();
    final records = await getRecords();
    final today = _todayRecord(records);
    final analytics = _analyticsService.calculate(records: records, goal: goal);
    return ActivityDashboardData(
      goal: goal,
      today: today,
      records: records,
      analytics: analytics,
    );
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  ActivityRecord? _todayRecord(List<ActivityRecord> records) {
    final todayKey = activityDateKey(DateTime.now());
    for (final r in records) {
      if (r.dateKey == todayKey) return r;
    }
    return null;
  }

  Future<void> _saveRecords(List<ActivityRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = records.toList()..sort((a, b) => b.date.compareTo(a.date));
    await prefs.setString(
      _recordsKey,
      jsonEncode(sorted.take(365).map((r) => r.toJson()).toList()),
    );
  }
}
