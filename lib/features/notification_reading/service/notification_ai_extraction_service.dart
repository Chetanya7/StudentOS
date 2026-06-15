import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../services/backend_ai_service.dart';
import '../models/notification_extraction.dart';
import '../models/notification_llm_input.dart';
import 'notification_prompt_builder.dart';

class NotificationAiExtractionService {
  const NotificationAiExtractionService({
    this.promptBuilder = const NotificationPromptBuilder(),
  });

  final NotificationPromptBuilder promptBuilder;
  static const BackendAiService _backendAiService = BackendAiService();

  Future<NotificationExtractionResult> extract(
    NotificationLlmInputPayload payload,
  ) async {
    final prompt = promptBuilder.buildStrictExtractionPrompt(payload);
    debugPrint('Notification extraction prompt:\n$prompt');

    try {
      final generatedText = await _backendAiService.postText(
        '/ai/notification/extract',
        {'payload': payload.toPromptJson()},
        timeout: const Duration(seconds: 90),
      );
      if (generatedText == null || generatedText.trim().isEmpty) {
        return _other('AI returned an empty response.');
      }

      final extraction = NotificationExtractionResult.fromJson(
        jsonDecode(_extractJsonObject(generatedText)) as Map<String, dynamic>,
      );
      return _fillMissingEventTimes(extraction, payload);
    } catch (e) {
      debugPrint('Notification extraction error: $e');
      return _other('AI extraction failed.');
    }
  }

  NotificationExtractionResult _fillMissingEventTimes(
    NotificationExtractionResult extraction,
    NotificationLlmInputPayload payload,
  ) {
    if (extraction.type != NotificationExtractionType.event ||
        extraction.startDateTime != null) {
      return extraction;
    }

    final sourceText = [
      payload.rawNotificationText,
      payload.messageText,
    ].whereType<String>().join(' ');
    final baseDate =
        DateTime.tryParse(payload.currentDate ?? '') ??
        DateTime.tryParse(payload.currentDateTime ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(payload.postTime);

    final parsed = _parseSimpleRelativeTimeRange(sourceText, baseDate);
    if (parsed == null) {
      return extraction;
    }

    return NotificationExtractionResult(
      type: extraction.type,
      startDateTime: parsed.$1,
      endDateTime: parsed.$2,
      isRepeating: extraction.isRepeating,
      repeat: extraction.repeat,
      summary: extraction.summary,
      timeZone: extraction.timeZone ?? payload.timeZone,
      nonEventReason: extraction.nonEventReason,
    );
  }

  (DateTime, DateTime)? _parseSimpleRelativeTimeRange(
    String text,
    DateTime baseDate,
  ) {
    final pattern = RegExp(
      r'\b(today|tomorrow)\b.*?(\d{1,2})[:.](\d{2})\s*(?:to|-)\s*(\d{1,2})[:.](\d{2})',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(text);
    if (match == null) return null;

    final dayWord = match.group(1)!.toLowerCase();
    final dayOffset = dayWord == 'tomorrow' ? 1 : 0;
    final date = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
    ).add(Duration(days: dayOffset));

    final start = DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    final end = DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
    );

    return (start, end.isAfter(start) ? end : end.add(const Duration(days: 1)));
  }

  NotificationExtractionResult _other(String reason) {
    return NotificationExtractionResult(
      type: NotificationExtractionType.other,
      isRepeating: false,
      nonEventReason: reason,
    );
  }

  String _extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');

    if (start == -1 || end == -1 || end <= start) {
      return text;
    }

    return text.substring(start, end + 1);
  }
}
