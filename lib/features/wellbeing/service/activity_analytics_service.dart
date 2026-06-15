import 'package:intl/intl.dart';

import '../models/activity_models.dart';

/// Computes activity analytics, scores, trends, and insights.
///
/// This service is stateless and testable.
class ActivityAnalyticsService {
  const ActivityAnalyticsService();

  ActivityAnalytics calculate({
    required List<ActivityRecord> records,
    required ActivityGoal goal,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final currentWeekRecords = _recordsInLastDays(records, 7, today);
    final previousWeekRecords = _recordsInRange(records, 14, 8, today);

    if (currentWeekRecords.isEmpty) {
      return ActivityAnalytics(
        averageSteps: 0,
        goalAchievementRate: 0,
        activityScore: 0,
        trendDirection: TrendDirection.stable,
        insights: [
          'Log your first activity to start building movement insights.',
          'Your daily step goal is ${formatStepsWithComma(goal.dailyStepGoal)} steps.',
        ],
        highestDay: null,
        lowestDay: null,
        goalMetDays: 0,
        totalDaysTracked: 0,
        previousWeekAverage: 0,
      );
    }

    final averageSteps = _average(
      currentWeekRecords.map((r) => r.steps),
    ).round();

    final goalMetDays = currentWeekRecords
        .where((r) => r.steps >= goal.dailyStepGoal)
        .length;

    final goalAchievementRate = goalMetDays / currentWeekRecords.length;

    final previousWeekAverage = previousWeekRecords.isEmpty
        ? 0
        : _average(previousWeekRecords.map((r) => r.steps)).round();

    final trendDirection = _detectTrend(averageSteps, previousWeekAverage);

    // Activity Score: 70% goal achievement + 30% consistency
    final todayRecord = _recordForDate(records, today);
    final todayAchievement = todayRecord == null
        ? 0.0
        : (todayRecord.steps / goal.dailyStepGoal).clamp(0, 1).toDouble();
    final weeklyAchievement = (averageSteps / goal.dailyStepGoal)
        .clamp(0, 1)
        .toDouble();
    final consistencyScore = _consistencyScore(currentWeekRecords, goal);
    final activityScore = ((weeklyAchievement * 70) + (consistencyScore * 0.30))
        .round()
        .clamp(0, 100);

    // Highest and lowest days
    final sorted = currentWeekRecords.toList()
      ..sort((a, b) => b.steps.compareTo(a.steps));
    final highestDay = sorted.first;
    final lowestDay = sorted.last;

    final insights = _generateInsights(
      records: currentWeekRecords,
      averageSteps: averageSteps,
      goalMetDays: goalMetDays,
      goal: goal,
      trendDirection: trendDirection,
      previousWeekAverage: previousWeekAverage,
      highestDay: highestDay,
    );

    return ActivityAnalytics(
      averageSteps: averageSteps,
      goalAchievementRate: goalAchievementRate,
      activityScore: activityScore,
      trendDirection: trendDirection,
      insights: insights,
      highestDay: highestDay,
      lowestDay: lowestDay,
      goalMetDays: goalMetDays,
      totalDaysTracked: currentWeekRecords.length,
      previousWeekAverage: previousWeekAverage,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  List<ActivityRecord> _recordsInLastDays(
    List<ActivityRecord> records,
    int days,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final earliest = today.subtract(Duration(days: days - 1));
    return records.where((r) {
      final date = DateTime(r.date.year, r.date.month, r.date.day);
      return !date.isBefore(earliest) && !date.isAfter(today);
    }).toList();
  }

  List<ActivityRecord> _recordsInRange(
    List<ActivityRecord> records,
    int startDaysAgo,
    int endDaysAgo,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final earliest = today.subtract(Duration(days: startDaysAgo - 1));
    final latest = today.subtract(Duration(days: endDaysAgo));
    return records.where((r) {
      final date = DateTime(r.date.year, r.date.month, r.date.day);
      return !date.isBefore(earliest) && !date.isAfter(latest);
    }).toList();
  }

  ActivityRecord? _recordForDate(List<ActivityRecord> records, DateTime date) {
    final key = activityDateKey(date);
    for (final r in records) {
      if (r.dateKey == key) return r;
    }
    return null;
  }

  TrendDirection _detectTrend(int currentAverage, int previousAverage) {
    if (previousAverage == 0) return TrendDirection.stable;
    final change = (currentAverage - previousAverage) / previousAverage;
    if (change > 0.10) return TrendDirection.improving;
    if (change < -0.10) return TrendDirection.declining;
    return TrendDirection.stable;
  }

  double _consistencyScore(List<ActivityRecord> records, ActivityGoal goal) {
    if (records.isEmpty) return 0;
    // Consistency = how many days had at least 50% of goal (partial credit approach)
    final scores = records.map((r) {
      return (r.steps / goal.dailyStepGoal).clamp(0, 1).toDouble();
    });
    return _average(scores) * 100;
  }

  List<String> _generateInsights({
    required List<ActivityRecord> records,
    required int averageSteps,
    required int goalMetDays,
    required ActivityGoal goal,
    required TrendDirection trendDirection,
    required int previousWeekAverage,
    required ActivityRecord? highestDay,
  }) {
    final insights = <String>[];

    // Goal achievement insight
    insights.add(
      'You met your activity goal on $goalMetDays of the last ${records.length} days.',
    );

    // Average steps insight
    insights.add(
      'Your average daily activity is ${formatStepsWithComma(averageSteps)} steps.',
    );

    // Trend insight
    if (previousWeekAverage > 0) {
      final percentChange =
          ((averageSteps - previousWeekAverage) / previousWeekAverage * 100)
              .round()
              .abs();
      if (trendDirection == TrendDirection.improving) {
        insights.add(
          'Your activity increased $percentChange% compared to last week.',
        );
      } else if (trendDirection == TrendDirection.declining) {
        insights.add(
          'Your activity declined $percentChange% compared to last week.',
        );
      }
    }

    // Highest day insight
    if (highestDay != null && records.length >= 3) {
      final dayName = DateFormat('EEEE').format(highestDay.date);
      insights.add('Your activity is highest on ${dayName}s.');
    }

    return insights.take(3).toList();
  }

  double _average(Iterable<num> values) {
    final list = values.toList();
    if (list.isEmpty) return 0;
    return list.fold<double>(0, (sum, v) => sum + v) / list.length;
  }
}
