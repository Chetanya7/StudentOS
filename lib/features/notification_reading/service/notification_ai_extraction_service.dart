import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../../../services/hugging_face_config.dart';
import '../models/notification_extraction.dart';
import '../models/notification_llm_input.dart';
import 'notification_prompt_builder.dart';

class NotificationAiExtractionService {
  const NotificationAiExtractionService({
    this.promptBuilder = const NotificationPromptBuilder(),
  });

  final NotificationPromptBuilder promptBuilder;

  Future<NotificationExtractionResult> extract(
    NotificationLlmInputPayload payload,
  ) async {
    final env = _loadedEnv();
    final modelId = HuggingFaceConfig.modelId(env['HF_MODEL_URL'] ?? '');
    final token = env['HF_TOKEN']?.trim() ?? '';

    if (modelId == null || token.isEmpty) {
      return _other('AI model is not configured.');
    }

    final prompt = promptBuilder.buildStrictExtractionPrompt(payload);
    debugPrint('Notification extraction prompt:\n$prompt');

    try {
      final response = await http
          .post(
            HuggingFaceConfig.chatCompletionsUri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': '$modelId:fastest',
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
              'max_tokens': 700,
              'temperature': 0.1,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Notification extraction failed: ${response.statusCode} ${response.body}',
        );
        return _other('AI request failed.');
      }

      final generatedText = _extractGeneratedText(response.body);
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

  Map<String, String> _loadedEnv() {
    try {
      return dotenv.env;
    } catch (_) {
      return const {};
    }
  }

  NotificationExtractionResult _other(String reason) {
    return NotificationExtractionResult(
      type: NotificationExtractionType.other,
      isRepeating: false,
      nonEventReason: reason,
    );
  }

  String? _extractGeneratedText(String responseBody) {
    final decoded = jsonDecode(responseBody);

    if (decoded is Map) {
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map) {
          final message = first['message'];
          if (message is Map && message['content'] != null) {
            return message['content'].toString();
          }
        }
      }
    }

    return null;
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
