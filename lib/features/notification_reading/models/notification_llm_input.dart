import 'notification_extraction.dart';

class NotificationActionContext {
  const NotificationActionContext({
    required this.title,
    required this.hasRemoteInputs,
    this.intentDescription,
  });

  final String? title;
  final bool hasRemoteInputs;
  final String? intentDescription;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (title != null) 'title': title,
      'hasRemoteInputs': hasRemoteInputs,
      if (intentDescription != null) 'intentDescription': intentDescription,
    };
  }

  factory NotificationActionContext.fromJson(Map<String, dynamic> json) {
    return NotificationActionContext(
      title: json['title']?.toString(),
      hasRemoteInputs: json['hasRemoteInputs'] == true,
      intentDescription: json['intentDescription']?.toString(),
    );
  }
}

class NotificationLlmInputPayload {
  const NotificationLlmInputPayload({
    required this.appPackageName,
    required this.notificationKey,
    required this.postTime,
    required this.rawNotificationTitle,
    required this.rawNotificationText,
    required this.extras,
    required this.actions,
    this.appLabel,
    this.channelId,
    this.category,
    this.isGroupConversation,
    this.senderName,
    this.messageText,
    this.conversationTitle,
    this.summary,
    this.timeZone,
  });

  /// Android package name such as `com.whatsapp`.
  final String appPackageName;

  /// Stable notification key from Android.
  final String notificationKey;

  /// Epoch milliseconds from Android.
  final int postTime;

  /// Common high-level notification fields that are usually visible in the status bar.
  final String? rawNotificationTitle;
  final String? rawNotificationText;
  final Map<String, dynamic> extras;
  final List<NotificationActionContext> actions;

  /// Helpful metadata when available.
  final String? appLabel;
  final String? channelId;
  final String? category;
  final bool? isGroupConversation;

  /// Parsed messaging hints when the source app exposes them.
  final String? senderName;
  final String? messageText;
  final String? conversationTitle;

  /// Optional context that can help the model reason about the time window.
  final String? summary;
  final String? timeZone;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'appPackageName': appPackageName,
      if (appLabel != null) 'appLabel': appLabel,
      'notificationKey': notificationKey,
      'postTime': postTime,
      if (channelId != null) 'channelId': channelId,
      if (category != null) 'category': category,
      if (rawNotificationTitle != null) 'rawNotificationTitle': rawNotificationTitle,
      if (rawNotificationText != null) 'rawNotificationText': rawNotificationText,
      if (isGroupConversation != null) 'isGroupConversation': isGroupConversation,
      if (senderName != null) 'senderName': senderName,
      if (messageText != null) 'messageText': messageText,
      if (conversationTitle != null) 'conversationTitle': conversationTitle,
      if (summary != null) 'summary': summary,
      if (timeZone != null) 'timeZone': timeZone,
      'extras': extras,
      'actions': actions.map((NotificationActionContext action) => action.toJson()).toList(),
    };
  }

  factory NotificationLlmInputPayload.fromJson(Map<String, dynamic> json) {
    final actionsJson = json['actions'];
    return NotificationLlmInputPayload(
      appPackageName: json['appPackageName']?.toString() ?? '',
      appLabel: json['appLabel']?.toString(),
      notificationKey: json['notificationKey']?.toString() ?? '',
      postTime: int.tryParse(json['postTime']?.toString() ?? '') ?? 0,
      channelId: json['channelId']?.toString(),
      category: json['category']?.toString(),
      rawNotificationTitle: json['rawNotificationTitle']?.toString(),
      rawNotificationText: json['rawNotificationText']?.toString(),
      isGroupConversation: json['isGroupConversation'] as bool?,
      senderName: json['senderName']?.toString(),
      messageText: json['messageText']?.toString(),
      conversationTitle: json['conversationTitle']?.toString(),
      summary: json['summary']?.toString(),
      timeZone: json['timeZone']?.toString(),
      extras: _readMap(json['extras']),
      actions: actionsJson is List
          ? actionsJson
              .whereType<Map>()
              .map((Map<dynamic, dynamic> item) => NotificationActionContext.fromJson(item.cast<String, dynamic>()))
              .toList()
          : <NotificationActionContext>[],
    );
  }

  static Map<String, dynamic> _readMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return value.cast<String, dynamic>();
    }

    return <String, dynamic>{};
  }

  NotificationExtractionResult buildExpectedEventSkeleton() {
    return NotificationExtractionResult(
      type: NotificationExtractionType.event,
      startDateTime: DateTime.fromMillisecondsSinceEpoch(postTime),
      endDateTime: DateTime.fromMillisecondsSinceEpoch(postTime),
      isRepeating: false,
      summary: summary,
      timeZone: timeZone,
    );
  }
}
