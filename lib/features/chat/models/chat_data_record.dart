enum ChatDataStream { scheduleData, financeData, wellbeingData, otherData }

extension ChatDataStreamJson on ChatDataStream {
  String get value {
    switch (this) {
      case ChatDataStream.scheduleData:
        return 'schedule_data';
      case ChatDataStream.financeData:
        return 'finance_data';
      case ChatDataStream.wellbeingData:
        return 'wellbeing_data';
      case ChatDataStream.otherData:
        return 'other_data';
    }
  }

  static ChatDataStream fromValue(String? value) {
    switch (value) {
      case 'schedule_data':
        return ChatDataStream.scheduleData;
      case 'finance_data':
        return ChatDataStream.financeData;
      case 'wellbeing_data':
        return ChatDataStream.wellbeingData;
      case 'other_data':
      default:
        return ChatDataStream.otherData;
    }
  }
}

class ChatDataRecord {
  const ChatDataRecord({
    required this.id,
    required this.stream,
    required this.subcategory,
    required this.title,
    required this.summary,
    required this.extractedText,
    required this.createdAt,
    this.structuredData = const <String, dynamic>{},
  });

  final String id;
  final ChatDataStream stream;
  final String subcategory;
  final String title;
  final String summary;
  final String extractedText;
  final DateTime createdAt;
  final Map<String, dynamic> structuredData;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'stream': stream.value,
      'subcategory': subcategory,
      'title': title,
      'summary': summary,
      'extractedText': extractedText,
      'createdAt': createdAt.toIso8601String(),
      'structuredData': structuredData,
    };
  }

  factory ChatDataRecord.fromJson(Map<String, dynamic> json) {
    return ChatDataRecord(
      id: json['id']?.toString() ?? '',
      stream: ChatDataStreamJson.fromValue(json['stream']?.toString()),
      subcategory: json['subcategory']?.toString() ?? 'general',
      title: json['title']?.toString() ?? 'Uploaded image',
      summary: json['summary']?.toString() ?? '',
      extractedText: json['extractedText']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      structuredData: json['structuredData'] is Map
          ? Map<String, dynamic>.from(json['structuredData'] as Map)
          : const <String, dynamic>{},
    );
  }
}
