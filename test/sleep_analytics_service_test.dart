import 'package:flutter_test/flutter_test.dart';
import 'package:studentos/features/wellbeing/models/sleep_models.dart';
import 'package:studentos/features/wellbeing/service/sleep_analytics_service.dart';

void main() {
  group('sleep duration', () {
    test('handles overnight sleep correctly', () {
      final duration = calculateSleepDurationMinutes(23 * 60 + 30, 7 * 60);

      expect(duration, 450);
      expect(formatSleepDuration(duration), '7h 30m');
    });
  });

  group('SleepAnalyticsService', () {
    const service = SleepAnalyticsService();
    const settings = SleepSettings(
      sleepGoalMinutes: 8 * 60,
      preferredBedtime: null,
      preferredWakeTime: null,
    );

    test('calculates weekly averages and excellent consistency', () {
      final today = DateTime(2026, 6, 15);
      final records = List.generate(7, (index) {
        final date = today.subtract(Duration(days: index));
        return SleepRecord(
          id: sleepDateKey(date),
          date: date,
          sleepTime: 23 * 60,
          wakeTime: 7 * 60,
          durationMinutes: 8 * 60,
        );
      });

      final analytics = service.calculate(
        records: records,
        settings: settings,
        now: today,
      );

      expect(analytics.averageSleep, 480);
      expect(analytics.averageBedtime, 23 * 60);
      expect(analytics.averageWakeTime, 7 * 60);
      expect(analytics.consistencyScore, 100);
      expect(analytics.sleepScore, 100);
      expect(analytics.goalMetDays, 7);
      expect(analytics.consistencyLabel, 'Excellent');
    });

    test('penalizes irregular timing and short sleep', () {
      final today = DateTime(2026, 6, 15);
      final bedtimes = [22 * 60, 23 * 60, 1 * 60, 2 * 60, 20 * 60, 0, 3 * 60];
      final wakeTimes = [
        6 * 60,
        7 * 60,
        8 * 60,
        10 * 60,
        5 * 60,
        9 * 60,
        11 * 60,
      ];
      final records = List.generate(7, (index) {
        final date = today.subtract(Duration(days: index));
        final duration = calculateSleepDurationMinutes(
          bedtimes[index],
          wakeTimes[index],
        );
        return SleepRecord(
          id: sleepDateKey(date),
          date: date,
          sleepTime: bedtimes[index],
          wakeTime: wakeTimes[index],
          durationMinutes: duration,
        );
      });

      final analytics = service.calculate(
        records: records,
        settings: settings,
        now: today,
      );

      expect(analytics.consistencyScore, lessThan(86));
      expect(analytics.sleepScore, inInclusiveRange(0, 100));
      expect(
        analytics.insights,
        contains('Your bedtime varies by more than 2 hours across the week.'),
      );
    });
  });
}
