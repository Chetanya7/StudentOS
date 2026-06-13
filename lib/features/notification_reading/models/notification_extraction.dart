enum NotificationExtractionType {
  event,
  other,
}

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
  const RepeatEncoding({
    required this.format,
    required this.value,
  });

  /// Suggested values: `rrule`, `cron`, or `human`.
  final String format;

  /// The encoded repeat definition. For `rrule`, use RFC 5545 style text.
  final String value;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'format': format,
      'value': value,
    };
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
    required this.startDateTime,
    required this.endDateTime,
    required this.isRepeating,
    this.repeat,
    this.summary,
    this.timeZone,
  });

  /// The current contract is `event`; the enum leaves room for future types.
  final NotificationExtractionType type;

  /// ISO 8601 datetime string, ideally with timezone offset.
  final DateTime startDateTime;

  /// ISO 8601 datetime string, ideally with timezone offset.
  final DateTime endDateTime;

  final bool isRepeating;
  final RepeatEncoding? repeat;
  final String? summary;
  final String? timeZone;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type.toJsonValue(),
      'startDateTime': startDateTime.toIso8601String(),
      'endDateTime': endDateTime.toIso8601String(),
      'isRepeating': isRepeating,
      if (repeat != null) 'repeat': repeat!.toJson(),
      if (summary != null) 'summary': summary,
      if (timeZone != null) 'timeZone': timeZone,
    };
  }

  factory NotificationExtractionResult.fromJson(Map<String, dynamic> json) {
    final repeatJson = json['repeat'];
    return NotificationExtractionResult(
      type: NotificationExtractionTypeJson.fromJsonValue(json['type']?.toString()),
      startDateTime: DateTime.parse(json['startDateTime'].toString()),
      endDateTime: DateTime.parse(json['endDateTime'].toString()),
      isRepeating: json['isRepeating'] == true,
      repeat: repeatJson is Map<String, dynamic>
          ? RepeatEncoding.fromJson(repeatJson)
          : repeatJson is Map
              ? RepeatEncoding.fromJson(repeatJson.cast<String, dynamic>())
              : null,
      summary: json['summary']?.toString(),
      timeZone: json['timeZone']?.toString(),
    );
  }
}
