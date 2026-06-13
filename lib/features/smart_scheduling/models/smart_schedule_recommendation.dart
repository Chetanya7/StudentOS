enum SmartScheduleRecommendationType { study, prepare, rest, plan }

extension SmartScheduleRecommendationTypeJson
    on SmartScheduleRecommendationType {
  String get jsonValue {
    switch (this) {
      case SmartScheduleRecommendationType.study:
        return 'study';
      case SmartScheduleRecommendationType.prepare:
        return 'prepare';
      case SmartScheduleRecommendationType.rest:
        return 'rest';
      case SmartScheduleRecommendationType.plan:
        return 'plan';
    }
  }

  static SmartScheduleRecommendationType fromJsonValue(String? value) {
    switch (value) {
      case 'study':
        return SmartScheduleRecommendationType.study;
      case 'prepare':
        return SmartScheduleRecommendationType.prepare;
      case 'rest':
        return SmartScheduleRecommendationType.rest;
      case 'plan':
      default:
        return SmartScheduleRecommendationType.plan;
    }
  }
}

class SmartScheduleRecommendation {
  const SmartScheduleRecommendation({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.reason,
    required this.suggestedDate,
    required this.priority,
  });

  final String id;
  final SmartScheduleRecommendationType type;
  final String title;
  final String message;
  final String reason;
  final DateTime suggestedDate;
  final int priority;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.jsonValue,
      'title': title,
      'message': message,
      'reason': reason,
      'suggestedDate': suggestedDate.toIso8601String(),
      'priority': priority,
    };
  }

  factory SmartScheduleRecommendation.fromJson(Map<String, dynamic> json) {
    return SmartScheduleRecommendation(
      id: json['id']?.toString() ?? '',
      type: SmartScheduleRecommendationTypeJson.fromJsonValue(
        json['type']?.toString(),
      ),
      title: json['title']?.toString() ?? 'Smart schedule tip',
      message: json['message']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      suggestedDate:
          DateTime.tryParse(json['suggestedDate']?.toString() ?? '') ??
          DateTime.now(),
      priority: int.tryParse(json['priority']?.toString() ?? '') ?? 3,
    );
  }
}
