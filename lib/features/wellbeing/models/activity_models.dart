/// Data source for an activity record.
enum ActivitySource { manual, healthConnect, healthKit, imported }

/// A single day's activity record.
class ActivityRecord {
  const ActivityRecord({
    required this.id,
    required this.date,
    required this.steps,
    required this.source,
  });

  final String id;
  final DateTime date;
  final int steps;
  final ActivitySource source;

  String get dateKey => activityDateKey(date);

  Map<String, dynamic> toJson() {
    return {'id': id, 'date': dateKey, 'steps': steps, 'source': source.name};
  }

  factory ActivityRecord.fromJson(Map<String, dynamic> json) {
    final dateText = json['date']?.toString() ?? '';
    final parsedDate = DateTime.tryParse(dateText) ?? DateTime.now();
    return ActivityRecord(
      id: json['id']?.toString() ?? activityDateKey(parsedDate),
      date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
      steps: _asInt(json['steps'], 0),
      source: _parseSource(json['source']),
    );
  }

  ActivityRecord copyWith({
    String? id,
    DateTime? date,
    int? steps,
    ActivitySource? source,
  }) {
    return ActivityRecord(
      id: id ?? this.id,
      date: date ?? this.date,
      steps: steps ?? this.steps,
      source: source ?? this.source,
    );
  }
}

/// User's activity goal configuration.
class ActivityGoal {
  const ActivityGoal({required this.dailyStepGoal});

  final int dailyStepGoal;

  static const defaults = ActivityGoal(dailyStepGoal: 8000);

  Map<String, dynamic> toJson() => {'dailyStepGoal': dailyStepGoal};

  factory ActivityGoal.fromJson(Map<String, dynamic> json) {
    return ActivityGoal(
      dailyStepGoal: _asInt(
        json['dailyStepGoal'],
        defaults.dailyStepGoal,
      ).clamp(1000, 50000),
    );
  }

  ActivityGoal copyWith({int? dailyStepGoal}) {
    return ActivityGoal(dailyStepGoal: dailyStepGoal ?? this.dailyStepGoal);
  }
}

/// Trend direction for weekly comparison.
enum TrendDirection { improving, stable, declining }

/// Computed analytics for activity data.
class ActivityAnalytics {
  const ActivityAnalytics({
    required this.averageSteps,
    required this.goalAchievementRate,
    required this.activityScore,
    required this.trendDirection,
    required this.insights,
    required this.highestDay,
    required this.lowestDay,
    required this.goalMetDays,
    required this.totalDaysTracked,
    required this.previousWeekAverage,
  });

  final int averageSteps;
  final double goalAchievementRate;
  final int activityScore;
  final TrendDirection trendDirection;
  final List<String> insights;
  final ActivityRecord? highestDay;
  final ActivityRecord? lowestDay;
  final int goalMetDays;
  final int totalDaysTracked;
  final int previousWeekAverage;

  String get scoreLabelText => activityScoreLabel(activityScore);

  String get trendText {
    switch (trendDirection) {
      case TrendDirection.improving:
        return 'Improving';
      case TrendDirection.stable:
        return 'Stable';
      case TrendDirection.declining:
        return 'Declining';
    }
  }

  String get trendDescription {
    if (previousWeekAverage == 0) {
      return 'Not enough data to compare weeks yet.';
    }
    final percentChange =
        ((averageSteps - previousWeekAverage) / previousWeekAverage * 100)
            .round()
            .abs();
    switch (trendDirection) {
      case TrendDirection.improving:
        return 'Your average activity increased by $percentChange% compared to last week.';
      case TrendDirection.stable:
        return 'Your activity has been stable compared to last week.';
      case TrendDirection.declining:
        return 'Your activity has declined by $percentChange% compared to last week.';
    }
  }
}

/// Aggregated dashboard data for the activity module.
class ActivityDashboardData {
  const ActivityDashboardData({
    required this.goal,
    required this.today,
    required this.records,
    required this.analytics,
  });

  final ActivityGoal goal;
  final ActivityRecord? today;
  final List<ActivityRecord> records;
  final ActivityAnalytics analytics;

  int get todaySteps => today?.steps ?? 0;

  double get goalProgress =>
      (todaySteps / goal.dailyStepGoal).clamp(0, 1).toDouble();

  int get goalPercentage => (goalProgress * 100).round();

  int get remainingSteps =>
      (goal.dailyStepGoal - todaySteps).clamp(0, goal.dailyStepGoal);
}

// =============================================================================
// Helpers
// =============================================================================

String activityDateKey(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

String formatSteps(int steps) {
  if (steps >= 1000) {
    final thousands = steps / 1000;
    if (steps % 1000 == 0) return '${thousands.toInt()}k';
    return '${thousands.toStringAsFixed(1)}k';
  }
  return steps.toString();
}

String formatStepsWithComma(int steps) {
  final str = steps.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(str[i]);
  }
  return buffer.toString();
}

String activityScoreLabel(int score) {
  if (score <= 40) return 'Low';
  if (score <= 70) return 'Fair';
  if (score <= 85) return 'Good';
  return 'Excellent';
}

String activityScoreExplanation(int score, TrendDirection trend) {
  if (score >= 86) {
    return 'You are consistently active and exceeding your daily goal.';
  }
  if (score >= 71) {
    return 'You are consistently active and close to your daily goal.';
  }
  if (score >= 41) {
    return 'You are moderately active. Try to be more consistent.';
  }
  return 'Your activity is low. Small daily walks can help.';
}

ActivitySource _parseSource(Object? value) {
  final name = value?.toString() ?? '';
  for (final source in ActivitySource.values) {
    if (source.name == name) return source;
  }
  return ActivitySource.manual;
}

int _asInt(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
