import 'package:shared_preferences/shared_preferences.dart';

class WellbeingService {
  static const _keyLastMorningDate = 'wellbeing_last_morning_date';
  static const _keyLastEveningDate = 'wellbeing_last_evening_date';

  /// Returns true if the app should show the wellbeing prompt now.
  /// This implements: once before 12:00 (morning) and once after 12:00 (evening)
  Future<bool> shouldPromptNow() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    final isMorning = now.hour < 12;

    if (isMorning) {
      final last = prefs.getString(_keyLastMorningDate);
      if (last == null) return true;
      final lastDate = DateTime.tryParse(last);
      if (lastDate == null) return true;
      return !_isSameLocalDay(lastDate, now);
    } else {
      final last = prefs.getString(_keyLastEveningDate);
      if (last == null) return true;
      final lastDate = DateTime.tryParse(last);
      if (lastDate == null) return true;
      return !_isSameLocalDay(lastDate, now);
    }
  }

  Future<void> markPromptShownNow() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    if (now.hour < 12) {
      await prefs.setString(_keyLastMorningDate, now.toIso8601String());
    } else {
      await prefs.setString(_keyLastEveningDate, now.toIso8601String());
    }
  }

  bool _isSameLocalDay(DateTime a, DateTime b) {
    final localA = a.toLocal();
    final localB = b.toLocal();
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }
}
