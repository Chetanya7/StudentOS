class HydrationSettings {
  const HydrationSettings({
    required this.enabled,
    required this.dailyGoalMl,
    required this.startMinutes,
    required this.endMinutes,
    required this.frequencyMinutes,
    required this.soundEnabled,
  });

  final bool enabled;
  final int dailyGoalMl;
  final int startMinutes;
  final int endMinutes;
  final int frequencyMinutes;
  final bool soundEnabled;

  static const defaults = HydrationSettings(
    enabled: false,
    dailyGoalMl: 2000,
    startMinutes: 8 * 60,
    endMinutes: 22 * 60,
    frequencyMinutes: 90,
    soundEnabled: true,
  );

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'dailyGoalMl': dailyGoalMl,
      'startMinutes': startMinutes,
      'endMinutes': endMinutes,
      'frequencyMinutes': frequencyMinutes,
      'soundEnabled': soundEnabled,
    };
  }

  factory HydrationSettings.fromJson(Map<String, dynamic> json) {
    return HydrationSettings(
      enabled: json['enabled'] == true,
      dailyGoalMl: _asInt(json['dailyGoalMl'], defaults.dailyGoalMl),
      startMinutes: _asInt(json['startMinutes'], defaults.startMinutes),
      endMinutes: _asInt(json['endMinutes'], defaults.endMinutes),
      frequencyMinutes: _asInt(
        json['frequencyMinutes'],
        defaults.frequencyMinutes,
      ),
      soundEnabled: json['soundEnabled'] != false,
    );
  }

  HydrationSettings copyWith({
    bool? enabled,
    int? dailyGoalMl,
    int? startMinutes,
    int? endMinutes,
    int? frequencyMinutes,
    bool? soundEnabled,
  }) {
    return HydrationSettings(
      enabled: enabled ?? this.enabled,
      dailyGoalMl: dailyGoalMl ?? this.dailyGoalMl,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      frequencyMinutes: frequencyMinutes ?? this.frequencyMinutes,
      soundEnabled: soundEnabled ?? this.soundEnabled,
    );
  }

  static int _asInt(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class HydrationDailyEntry {
  const HydrationDailyEntry({
    required this.date,
    required this.amountMl,
    required this.goalMl,
  });

  final String date;
  final int amountMl;
  final int goalMl;

  bool get isComplete => amountMl >= goalMl;

  Map<String, dynamic> toJson() {
    return {'date': date, 'amountMl': amountMl, 'goalMl': goalMl};
  }

  factory HydrationDailyEntry.fromJson(Map<String, dynamic> json) {
    return HydrationDailyEntry(
      date: json['date']?.toString() ?? '',
      amountMl: HydrationSettings._asInt(json['amountMl'], 0),
      goalMl: HydrationSettings._asInt(
        json['goalMl'],
        HydrationSettings.defaults.dailyGoalMl,
      ),
    );
  }
}

class HydrationSummary {
  const HydrationSummary({
    required this.settings,
    required this.today,
    required this.weeklyAverageMl,
    required this.goalCompletionRate,
    required this.streakDays,
  });

  final HydrationSettings settings;
  final HydrationDailyEntry today;
  final double weeklyAverageMl;
  final double goalCompletionRate;
  final int streakDays;

  double get progress {
    if (today.goalMl <= 0) return 0;
    return (today.amountMl / today.goalMl).clamp(0, 1).toDouble();
  }

  int get remainingMl => (today.goalMl - today.amountMl).clamp(0, today.goalMl);
  int get percentComplete => (progress * 100).round();
}
