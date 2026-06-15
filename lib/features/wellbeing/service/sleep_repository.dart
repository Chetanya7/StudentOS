import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sleep_models.dart';
import 'sleep_analytics_service.dart';

class SleepRepository {
  SleepRepository({SleepAnalyticsService? analyticsService})
    : _analyticsService = analyticsService ?? const SleepAnalyticsService();

  static const settingsKey = 'sleep_settings_json';
  static const recordsKey = 'sleep_records_json';

  final SleepAnalyticsService _analyticsService;
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  Future<SleepSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(settingsKey);
    if (source == null || source.isEmpty) return SleepSettings.defaults;

    try {
      final decoded = jsonDecode(source);
      if (decoded is Map) {
        return SleepSettings.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {
      // Malformed local data should not block the wellbeing tab.
    }

    return SleepSettings.defaults;
  }

  Future<void> saveSettings(SleepSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(settingsKey, jsonEncode(settings.toJson()));
    changes.value++;
  }

  Future<List<SleepRecord>> getRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(recordsKey);
    if (source == null || source.isEmpty) return <SleepRecord>[];

    try {
      final decoded = jsonDecode(source);
      if (decoded is List) {
        final records =
            decoded
                .whereType<Map>()
                .map(
                  (item) => SleepRecord.fromJson(item.cast<String, dynamic>()),
                )
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date));
        return records;
      }
    } catch (_) {
      // Keep the app usable when old local data is malformed.
    }

    return <SleepRecord>[];
  }

  Future<SleepRecord?> getRecordForDate(DateTime date) async {
    final key = sleepDateKey(date);
    final records = await getRecords();
    for (final record in records) {
      if (record.dateKey == key) return record;
    }
    return null;
  }

  Future<SleepRecord> upsertRecord({
    required DateTime date,
    required int sleepTime,
    required int wakeTime,
  }) async {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final key = sleepDateKey(normalizedDate);
    final record = SleepRecord(
      id: key,
      date: normalizedDate,
      sleepTime: sleepTime,
      wakeTime: wakeTime,
      durationMinutes: calculateSleepDurationMinutes(sleepTime, wakeTime),
    );

    final records = await getRecords();
    final index = records.indexWhere((item) => item.dateKey == key);
    if (index == -1) {
      records.add(record);
    } else {
      records[index] = record;
    }
    await _saveRecords(records);
    changes.value++;
    return record;
  }

  Future<SleepDashboardData> getDashboardData() async {
    final settings = await getSettings();
    final records = await getRecords();
    final analytics = _analyticsService.calculate(
      records: records,
      settings: settings,
    );
    return SleepDashboardData(
      settings: settings,
      records: records,
      analytics: analytics,
      lastNight: records.isEmpty ? null : records.first,
    );
  }

  Future<void> _saveRecords(List<SleepRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = records.toList()..sort((a, b) => b.date.compareTo(a.date));
    await prefs.setString(
      recordsKey,
      jsonEncode(sorted.take(365).map((record) => record.toJson()).toList()),
    );
  }
}
