enum NotificationExtractionType { event, other }

extension NotificationExtractionTypeJson on NotificationExtractionType {
  String toJsonValue() {
    switch (this) {
      case NotificationExtractionType.event:
        return 'event';
      case NotificationExtractionType.other:
        return 'other';
    }
  }

  static NotificationExtractionType fromJsonValue(String? value) {
    switch (value) {
      case 'event':
        return NotificationExtractionType.event;
      case 'other':
      default:
        return NotificationExtractionType.other;
    }
  }
}

class RepeatEncoding {
  const RepeatEncoding({required this.format, required this.value});

  /// Suggested values: `rrule`, `cron`, or `human`.
  final String format;

  /// The encoded repeat definition. For `rrule`, use RFC 5545 style text.
  final String value;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'format': format, 'value': value};
  }

  factory RepeatEncoding.fromJson(Map<String, dynamic> json) {
    return RepeatEncoding(
      format: json['format']?.toString() ?? 'rrule',
      value: json['value']?.toString() ?? '',
    );
  }
}

class NotificationExtractionResult {
  const NotificationExtractionResult({
    required this.type,
    required this.isRepeating,
    this.startDateTime,
    this.endDateTime,
    this.repeat,
    this.summary,
    this.timeZone,
    this.nonEventReason,
  });

  final NotificationExtractionType type;

  /// ISO 8601 datetime string, ideally with timezone offset.
  final DateTime? startDateTime;

  /// ISO 8601 datetime string, ideally with timezone offset.
  final DateTime? endDateTime;

  final bool isRepeating;
  final RepeatEncoding? repeat;
  final String? summary;
  final String? timeZone;
  final String? nonEventReason;

  bool get canCreateCalendarEvent {
    return type == NotificationExtractionType.event && startDateTime != null;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type.toJsonValue(),
      'startDateTime': startDateTime?.toIso8601String(),
      'endDateTime': endDateTime?.toIso8601String(),
      'isRepeating': isRepeating,
      if (repeat != null) 'repeat': repeat!.toJson(),
      if (summary != null) 'summary': summary,
      if (timeZone != null) 'timeZone': timeZone,
      if (nonEventReason != null) 'nonEventReason': nonEventReason,
    };
  }

  factory NotificationExtractionResult.fromJson(Map<String, dynamic> json) {
    final repeatJson = json['repeat'];
    return NotificationExtractionResult(
      type: NotificationExtractionTypeJson.fromJsonValue(
        json['type']?.toString(),
      ),
      startDateTime: DateTime.tryParse(json['startDateTime']?.toString() ?? ''),
      endDateTime: DateTime.tryParse(json['endDateTime']?.toString() ?? ''),
      isRepeating: json['isRepeating'] == true,
      repeat: repeatJson is Map<String, dynamic>
          ? RepeatEncoding.fromJson(repeatJson)
          : repeatJson is Map
          ? RepeatEncoding.fromJson(repeatJson.cast<String, dynamic>())
          : null,
      summary: json['summary']?.toString(),
      timeZone: json['timeZone']?.toString(),
      nonEventReason: json['nonEventReason']?.toString(),
    );
  }
}
