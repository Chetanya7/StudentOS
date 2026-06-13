import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../../../models/calendar_event.dart';
import '../../../services/hugging_face_config.dart';
import '../models/chat_message.dart';

class CalendarChatService {
  const CalendarChatService();

  Future<String> summarizeSchedule({
    required List<CalendarEvent> events,
    DateTime? now,
  }) async {
    final prompt = _buildSummaryPrompt(
      events: events,
      now: now ?? DateTime.now(),
    );
    final response = await _callHuggingFace(prompt);

    if (response != null && response.trim().isNotEmpty) {
      return _cleanText(response);
    }

    return _fallbackSummary(events);
  }

  Future<String> answerQuestion({
    required String question,
    required List<CalendarEvent> events,
    required List<ChatMessage> history,
    DateTime? now,
  }) async {
    final prompt = _buildQuestionPrompt(
      question: question,
      events: events,
      history: history,
      now: now ?? DateTime.now(),
    );
    final response = await _callHuggingFace(prompt);

    if (response != null && response.trim().isNotEmpty) {
      return _cleanText(response);
    }

    return 'I could not reach the AI model, but I can see ${events.length} calendar events for this week.';
  }

  String _buildSummaryPrompt({
    required List<CalendarEvent> events,
    required DateTime now,
  }) {
    return '''
You are StudentOS, a concise academic assistant.

Summarize the student's calendar for the week. Mention busy days, quizzes, exams, assignments, deadlines, and preparation advice. Keep it short and useful.

Current time: ${now.toIso8601String()}

Calendar events:
${const JsonEncoder.withIndent('  ').convert(events.map((event) => event.toJson()).toList())}

Return only the summary text. Do not return JSON.
''';
  }

  String _buildQuestionPrompt({
    required String question,
    required List<CalendarEvent> events,
    required List<ChatMessage> history,
    required DateTime now,
  }) {
    final recentHistory = history
        .take(8)
        .map(
          (message) => {
            'role': message.role == ChatMessageRole.user ? 'user' : 'assistant',
            'text': message.text,
          },
        )
        .toList();

    final payload = {
      'now': now.toIso8601String(),
      'availableDataCategories': ['calendar_events'],
      'calendarEvents': events.map((event) => event.toJson()).toList(),
      'recentChatHistory': recentHistory,
      'question': question,
    };

    return '''
You are StudentOS, a helpful academic assistant.

Answer the student's question using only the data provided. For now, the only available data category is calendar_events. If the answer is not in the calendar data, say what is missing and give a reasonable next step.

Later this prompt may become an agentic loop where you choose which data category or tool to inspect. For now, inspect the calendar_events directly.

Keep the answer concise and practical.

Payload:
${const JsonEncoder.withIndent('  ').convert(payload)}

Return only the answer text. Do not return JSON.
''';
  }

  Future<String?> _callHuggingFace(String prompt) async {
    final env = _loadedEnv();
    final modelUrl = env['HF_MODEL_URL']?.trim() ?? '';
    final modelId = HuggingFaceConfig.modelId(modelUrl);
    final token = env['HF_TOKEN']?.trim() ?? '';

    if (modelId == null || token.isEmpty) {
      return null;
    }

    try {
      debugPrint('Chat prompt:\n$prompt');

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
              'max_tokens': 500,
              'temperature': 0.3,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Hugging Face chat failed: ${response.statusCode} ${response.body}',
        );
        return null;
      }

      return _extractGeneratedText(response.body);
    } catch (e) {
      debugPrint('Hugging Face chat error: $e');
      return null;
    }
  }

  Map<String, String> _loadedEnv() {
    try {
      return dotenv.env;
    } catch (_) {
      return const {};
    }
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

    if (decoded is List && decoded.isNotEmpty) {
      final first = decoded.first;
      if (first is Map && first['generated_text'] != null) {
        return first['generated_text'].toString();
      }
    }

    if (decoded is Map) {
      if (decoded['generated_text'] != null) {
        return decoded['generated_text'].toString();
      }

      if (decoded['error'] != null) {
        debugPrint('Hugging Face chat error: ${decoded['error']}');
      }
    }

    return null;
  }

  String _cleanText(String text) {
    return text.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  String _fallbackSummary(List<CalendarEvent> events) {
    if (events.isEmpty) {
      return 'Your calendar is clear for the week.';
    }

    final academicEvents = events.where((event) {
      return RegExp(
        r'\b(quiz|exam|test|midterm|final|assignment|deadline|presentation|project|lab)\b',
        caseSensitive: false,
      ).hasMatch(event.title);
    }).toList();

    if (academicEvents.isEmpty) {
      return 'You have ${events.length} events this week and no obvious quizzes, assignments, or deadlines on the calendar.';
    }

    return 'You have ${events.length} events this week, including ${academicEvents.length} academic item(s) that may need prep.';
  }
}
