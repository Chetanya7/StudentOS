import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../notification_reading/service/notification_service.dart';
import '../models/hydration_models.dart';

class HydrationService {
  HydrationService({NotificationService? notificationService})
    : _notificationService = notificationService ?? NotificationService();

  static const settingsKey = 'hydration_settings_json';
  static const entriesKey = 'hydration_entries_json';

  final NotificationService _notificationService;
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  Future<HydrationSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(settingsKey);
    if (source == null || source.isEmpty) {
      return HydrationSettings.defaults;
    }

    try {
      final decoded = jsonDecode(source);
      if (decoded is Map) {
        return HydrationSettings.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {
      // Fall through to defaults when a legacy value is malformed.
    }

    return HydrationSettings.defaults;
  }

  Future<void> saveSettings(HydrationSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(settingsKey, jsonEncode(settings.toJson()));
    if (settings.enabled) {
      await _notificationService.scheduleHydrationReminders(settings);
    } else {
      await _notificationService.cancelHydrationReminders();
    }
    changes.value++;
  }

  Future<HydrationSummary> getSummary() async {
    final settings = await getSettings();
    final entries = await _getEntries();
    final todayDate = _dateKey(DateTime.now());
    final today = entries[todayDate] ??
        HydrationDailyEntry(
          date: todayDate,
          amountMl: 0,
          goalMl: settings.dailyGoalMl,
        );

    return HydrationSummary(
      settings: settings,
      today: today,
      weeklyAverageMl: _weeklyAverage(entries),
      goalCompletionRate: _completionRate(entries),
      streakDays: _streak(entries),
    );
  }

  Future<HydrationSummary> addWater({int amountMl = 250}) async {
    final settings = await getSettings();
    final entries = await _getEntries();
    final todayDate = _dateKey(DateTime.now());
    final current = entries[todayDate] ??
        HydrationDailyEntry(
          date: todayDate,
          amountMl: 0,
          goalMl: settings.dailyGoalMl,
        );

    entries[todayDate] = HydrationDailyEntry(
      date: todayDate,
      amountMl: current.amountMl + amountMl,
      goalMl: settings.dailyGoalMl,
    );

    await _saveEntries(entries);
    if (settings.enabled) {
      await _notificationService.scheduleHydrationReminders(settings);
    }
    changes.value++;
    return getSummary();
  }

  Future<Map<String, HydrationDailyEntry>> _getEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(entriesKey);
    if (source == null || source.isEmpty) return <String, HydrationDailyEntry>{};

    try {
      final decoded = jsonDecode(source);
      if (decoded is List) {
        return {
          for (final item in decoded.whereType<Map>())
            HydrationDailyEntry.fromJson(item.cast<String, dynamic>()).date:
                HydrationDailyEntry.fromJson(item.cast<String, dynamic>()),
        }..remove('');
      }
    } catch (_) {
      // Keep the app usable if old local data is malformed.
    }

    return <String, HydrationDailyEntry>{};
  }

  Future<void> _saveEntries(Map<String, HydrationDailyEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = entries.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    await prefs.setString(
      entriesKey,
      jsonEncode(sorted.take(120).map((entry) => entry.toJson()).toList()),
    );
  }

  double _weeklyAverage(Map<String, HydrationDailyEntry> entries) {
    final dates = _recentDateKeys(7);
    if (dates.isEmpty) return 0;
    final total = dates.fold<int>(
      0,
      (sum, date) => sum + (entries[date]?.amountMl ?? 0),
    );
    return total / dates.length;
  }

  double _completionRate(Map<String, HydrationDailyEntry> entries) {
    final dates = _recentDateKeys(7);
    if (dates.isEmpty) return 0;
    final completed = dates
        .where((date) => entries[date]?.isComplete ?? false)
        .length;
    return completed / dates.length;
  }

  int _streak(Map<String, HydrationDailyEntry> entries) {
    var streak = 0;
    var cursor = DateTime.now();
    while (true) {
      final entry = entries[_dateKey(cursor)];
      if (entry == null || !entry.isComplete) return streak;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
  }

  List<String> _recentDateKeys(int count) {
    final now = DateTime.now();
    return List.generate(
      count,
      (index) => _dateKey(now.subtract(Duration(days: index))),
    );
  }

  String _dateKey(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}
