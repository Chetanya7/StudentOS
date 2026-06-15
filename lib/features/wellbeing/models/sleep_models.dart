class SleepRecord {
  const SleepRecord({
    required this.id,
    required this.date,
    required this.sleepTime,
    required this.wakeTime,
    required this.durationMinutes,
    this.source = SleepSource.manual,
  });

  final String id;
  final DateTime date;
  final int sleepTime;
  final int wakeTime;
  final int durationMinutes;
  final SleepSource source;

  String get dateKey => sleepDateKey(date);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': dateKey,
      'sleepTime': sleepTime,
      'wakeTime': wakeTime,
      'durationMinutes': durationMinutes,
      'source': source.name,
    };
  }

  factory SleepRecord.fromJson(Map<String, dynamic> json) {
    final dateText = json['date']?.toString() ?? '';
    final parsedDate = DateTime.tryParse(dateText) ?? DateTime.now();
    final sleepTime = _asInt(json['sleepTime'], 23 * 60);
    final wakeTime = _asInt(json['wakeTime'], 7 * 60);
    return SleepRecord(
      id: json['id']?.toString().isNotEmpty == true
          ? json['id'].toString()
          : sleepDateKey(parsedDate),
      date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
      sleepTime: sleepTime,
      wakeTime: wakeTime,
      durationMinutes: _asInt(
        json['durationMinutes'],
        calculateSleepDurationMinutes(sleepTime, wakeTime),
      ),
      source: _parseSleepSource(json['source']),
    );
  }

  SleepRecord copyWith({
    String? id,
    DateTime? date,
    int? sleepTime,
    int? wakeTime,
    int? durationMinutes,
    SleepSource? source,
  }) {
    return SleepRecord(
      id: id ?? this.id,
      date: date ?? this.date,
      sleepTime: sleepTime ?? this.sleepTime,
      wakeTime: wakeTime ?? this.wakeTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      source: source ?? this.source,
    );
  }
}

/// Data source for a sleep record.
enum SleepSource { manual, healthConnect, healthKit, imported }

class SleepSettings {
  const SleepSettings({
    required this.sleepGoalMinutes,
    required this.preferredBedtime,
    required this.preferredWakeTime,
  });

  final int sleepGoalMinutes;
  final int? preferredBedtime;
  final int? preferredWakeTime;

  static const defaults = SleepSettings(
    sleepGoalMinutes: 8 * 60,
    preferredBedtime: null,
    preferredWakeTime: null,
  );

  Map<String, dynamic> toJson() {
    return {
      'sleepGoalMinutes': sleepGoalMinutes,
      'preferredBedtime': preferredBedtime,
      'preferredWakeTime': preferredWakeTime,
    };
  }

  factory SleepSettings.fromJson(Map<String, dynamic> json) {
    return SleepSettings(
      sleepGoalMinutes: _asInt(
        json['sleepGoalMinutes'],
        defaults.sleepGoalMinutes,
      ).clamp(60, 16 * 60).toInt(),
      preferredBedtime: _nullableMinutes(json['preferredBedtime']),
      preferredWakeTime: _nullableMinutes(json['preferredWakeTime']),
    );
  }

  SleepSettings copyWith({
    int? sleepGoalMinutes,
    Object? preferredBedtime = _unset,
    Object? preferredWakeTime = _unset,
  }) {
    return SleepSettings(
      sleepGoalMinutes: sleepGoalMinutes ?? this.sleepGoalMinutes,
      preferredBedtime: preferredBedtime == _unset
          ? this.preferredBedtime
          : preferredBedtime as int?,
      preferredWakeTime: preferredWakeTime == _unset
          ? this.preferredWakeTime
          : preferredWakeTime as int?,
    );
  }
}

class SleepAnalytics {
  const SleepAnalytics({
    required this.averageSleep,
    required this.averageBedtime,
    required this.averageWakeTime,
    required this.consistencyScore,
    required this.sleepScore,
    required this.goalMetDays,
    required this.insights,
  });

  final int averageSleep;
  final int? averageBedtime;
  final int? averageWakeTime;
  final int consistencyScore;
  final int sleepScore;
  final int goalMetDays;
  final List<String> insights;

  String get consistencyLabel => sleepScoreLabel(consistencyScore);
  String get sleepScoreLabelText => sleepScoreLabel(sleepScore);
}

class SleepDashboardData {
  const SleepDashboardData({
    required this.settings,
    required this.records,
    required this.analytics,
    required this.lastNight,
  });

  final SleepSettings settings;
  final List<SleepRecord> records;
  final SleepAnalytics analytics;
  final SleepRecord? lastNight;
}

const Object _unset = Object();

int calculateSleepDurationMinutes(int sleepTime, int wakeTime) {
  final normalizedSleep = sleepTime % (24 * 60);
  final normalizedWake = wakeTime % (24 * 60);
  var duration = normalizedWake - normalizedSleep;
  if (duration <= 0) duration += 24 * 60;
  return duration;
}

String sleepDateKey(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

String formatSleepDuration(int minutes) {
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return '${mins}m';
  if (mins == 0) return '${hours}h';
  return '${hours}h ${mins}m';
}

String formatSleepClock(int minutes) {
  final normalized = minutes % (24 * 60);
  final hour = normalized ~/ 60;
  final minute = normalized % 60;
  final suffix = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
}

String sleepScoreLabel(int score) {
  if (score <= 40) return 'Poor';
  if (score <= 70) return 'Fair';
  if (score <= 85) return 'Good';
  return 'Excellent';
}

int _asInt(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int? _nullableMinutes(Object? value) {
  if (value == null) return null;
  final parsed = _asInt(value, -1);
  if (parsed < 0) return null;
  return parsed.clamp(0, (24 * 60) - 1);
}

SleepSource _parseSleepSource(Object? value) {
  final name = value?.toString() ?? '';
  for (final source in SleepSource.values) {
    if (source.name == name) return source;
  }
  return SleepSource.manual;
}
