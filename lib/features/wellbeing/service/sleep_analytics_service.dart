import 'dart:math';

import '../models/sleep_models.dart';

class SleepAnalyticsService {
  const SleepAnalyticsService();

  SleepAnalytics calculate({
    required List<SleepRecord> records,
    required SleepSettings settings,
    DateTime? now,
  }) {
    final weeklyRecords = _recordsInLastDays(records, 7, now ?? DateTime.now());
    if (weeklyRecords.isEmpty) {
      return const SleepAnalytics(
        averageSleep: 0,
        averageBedtime: null,
        averageWakeTime: null,
        consistencyScore: 0,
        sleepScore: 0,
        goalMetDays: 0,
        insights: [
          'Log your first night to start building sleep insights.',
          'Your sleep goal is set to 8h by default.',
        ],
      );
    }

    final averageSleep = _average(
      weeklyRecords.map((record) => record.durationMinutes),
    ).round();
    final averageBedtime = _circularAverage(
      weeklyRecords.map((record) => record.sleepTime),
    );
    final averageWakeTime = _circularAverage(
      weeklyRecords.map((record) => record.wakeTime),
    );
    final consistencyScore = _consistencyScore(
      weeklyRecords,
      averageBedtime,
      averageWakeTime,
    );
    final durationAchievement = (averageSleep / settings.sleepGoalMinutes)
        .clamp(0, 1)
        .toDouble();
    final sleepScore = ((durationAchievement * 70) + (consistencyScore * 0.30))
        .round();
    final goalMetDays = weeklyRecords
        .where((record) => record.durationMinutes >= settings.sleepGoalMinutes)
        .length;

    return SleepAnalytics(
      averageSleep: averageSleep,
      averageBedtime: averageBedtime,
      averageWakeTime: averageWakeTime,
      consistencyScore: consistencyScore,
      sleepScore: sleepScore.clamp(0, 100).toInt(),
      goalMetDays: goalMetDays,
      insights: _insights(
        weeklyRecords: weeklyRecords,
        averageSleep: averageSleep,
        averageBedtime: averageBedtime,
        goalMetDays: goalMetDays,
        consistencyScore: consistencyScore,
      ),
    );
  }

  List<SleepRecord> _recordsInLastDays(
    List<SleepRecord> records,
    int days,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final earliest = today.subtract(Duration(days: days - 1));
    return records.where((record) {
      final date = DateTime(
        record.date.year,
        record.date.month,
        record.date.day,
      );
      return !date.isBefore(earliest) && !date.isAfter(today);
    }).toList();
  }

  int _consistencyScore(
    List<SleepRecord> records,
    int? averageBedtime,
    int? averageWakeTime,
  ) {
    if (records.isEmpty || averageBedtime == null || averageWakeTime == null) {
      return 0;
    }

    final deviations = records.map((record) {
      final bedtimeDeviation = _minuteDeviation(
        record.sleepTime,
        averageBedtime,
      );
      final wakeDeviation = _minuteDeviation(record.wakeTime, averageWakeTime);
      return (bedtimeDeviation + wakeDeviation) / 2;
    });
    final averageDeviation = _average(deviations);
    final score = 100 - (averageDeviation / 180 * 100);
    return score.round().clamp(0, 100);
  }

  List<String> _insights({
    required List<SleepRecord> weeklyRecords,
    required int averageSleep,
    required int? averageBedtime,
    required int goalMetDays,
    required int consistencyScore,
  }) {
    final insights = <String>[
      'You slept an average of ${formatSleepDuration(averageSleep)} this week.',
      if (averageBedtime != null)
        'Your average bedtime is ${formatSleepClock(averageBedtime)}.',
    ];

    if (consistencyScore >= 86) {
      insights.add('Your sleep schedule is highly consistent.');
    } else if (_bedtimeRange(weeklyRecords) > 120) {
      insights.add('Your bedtime varies by more than 2 hours across the week.');
    } else if (consistencyScore >= 71) {
      insights.add('Your sleep timing is trending steady.');
    } else {
      insights.add('A steadier bedtime and wake time can lift your score.');
    }

    insights.add('You met your sleep goal on $goalMetDays of the last 7 days.');
    return insights.take(3).toList();
  }

  int _bedtimeRange(List<SleepRecord> records) {
    if (records.length < 2) return 0;
    final bedtimes = records.map((record) => record.sleepTime).toList()..sort();
    var largestGap = 0;
    for (var index = 1; index < bedtimes.length; index++) {
      largestGap = max(largestGap, bedtimes[index] - bedtimes[index - 1]);
    }
    largestGap = max(largestGap, bedtimes.first + (24 * 60) - bedtimes.last);
    return (24 * 60) - largestGap;
  }

  double _average(Iterable<num> values) {
    final list = values.toList();
    if (list.isEmpty) return 0;
    return list.fold<double>(0, (sum, value) => sum + value) / list.length;
  }

  int _circularAverage(Iterable<int> minutes) {
    final list = minutes.toList();
    if (list.isEmpty) return 0;
    var sinSum = 0.0;
    var cosSum = 0.0;
    for (final minute in list) {
      final angle = (minute / (24 * 60)) * 2 * pi;
      sinSum += sin(angle);
      cosSum += cos(angle);
    }
    final angle = atan2(sinSum / list.length, cosSum / list.length);
    final normalized = angle < 0 ? angle + (2 * pi) : angle;
    return ((normalized / (2 * pi)) * 24 * 60).round() % (24 * 60);
  }

  int _minuteDeviation(int a, int b) {
    final diff = (a - b).abs();
    return min(diff, (24 * 60) - diff);
  }
}
