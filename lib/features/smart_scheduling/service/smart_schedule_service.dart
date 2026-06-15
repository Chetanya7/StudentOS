import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../models/calendar_event.dart';
import '../../../services/backend_ai_service.dart';
import '../models/smart_schedule_recommendation.dart';

class SmartScheduleService {
  const SmartScheduleService();

  static const BackendAiService _backendAiService = BackendAiService();

  String buildPrompt({
    required List<CalendarEvent> events,
    required DateTime now,
  }) {
    final payload = {
      'now': now.toIso8601String(),
      'timezone': now.timeZoneName,
      'calendarEvents': events.map((event) => event.toJson()).toList(),
    };

    return '''
You are StudentOS, a calm academic planning assistant.

Given this week's calendar events, return JSON only. Recommend small, actionable scheduling advice for a student. Prefer advice that anticipates upcoming academic deadlines, quizzes, exams, assignments, project meetings, presentations, and busy days.

Rules:
- Return 0 to 5 recommendations.
- Each recommendation should be useful today or in the next few days.
- If a quiz/exam/deadline is soon and the student is busy before it, recommend studying earlier.
- Do not invent calendar events.
- Keep messages short enough for a phone notification.

Return this exact shape:
{
  "recommendations": [
    {
      "id": "stable-short-id",
      "type": "study|prepare|rest|plan",
      "title": "short title",
      "message": "student-facing advice",
      "reason": "why this advice follows from the calendar",
      "suggestedDate": "ISO-8601 datetime",
      "priority": 1
    }
  ]
}

Calendar payload:
${const JsonEncoder.withIndent('  ').convert(payload)}
''';
  }

  List<SmartScheduleRecommendation> parseRecommendationsJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      return const [];
    }

    final recommendations = decoded['recommendations'];
    if (recommendations is! List) {
      return const [];
    }

    return recommendations
        .whereType<Map>()
        .map(
          (json) => SmartScheduleRecommendation.fromJson(
            json.cast<String, dynamic>(),
          ),
        )
        .where((recommendation) => recommendation.message.isNotEmpty)
        .toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
  }

  Future<List<SmartScheduleRecommendation>> getRecommendations({
    required List<CalendarEvent> events,
    DateTime? now,
  }) async {
    final currentTime = now ?? DateTime.now();
    final aiRecommendations = await _getBackendRecommendations(
      events: events,
      now: currentTime,
    );

    if (aiRecommendations.isNotEmpty) {
      return aiRecommendations;
    }

    return _buildFallbackRecommendations(events: events, now: currentTime);
  }

  Future<List<SmartScheduleRecommendation>> _getBackendRecommendations({
    required List<CalendarEvent> events,
    required DateTime now,
  }) async {
    try {
      final prompt = buildPrompt(events: events, now: now);
      debugPrint('Smart scheduling prompt:\n$prompt');
      final generatedText = await _backendAiService
          .postText('/ai/smart-schedule', {
            'now': now.toIso8601String(),
            'timezone': now.timeZoneName,
            'calendar_events': events.map((event) => event.toJson()).toList(),
          }, timeout: const Duration(seconds: 90));
      if (generatedText == null || generatedText.trim().isEmpty) {
        return const [];
      }

      return parseRecommendationsJson(_extractJsonObject(generatedText));
    } catch (e) {
      debugPrint('Backend smart scheduling error: $e');
      return const [];
    }
  }

  String _extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');

    if (start == -1 || end == -1 || end <= start) {
      return text;
    }

    return text.substring(start, end + 1);
  }

  List<SmartScheduleRecommendation> _buildFallbackRecommendations({
    required List<CalendarEvent> events,
    required DateTime now,
  }) {
    final upcoming = events.where((event) => event.start.isAfter(now)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final recommendations = <SmartScheduleRecommendation>[];
    final academicKeywords = RegExp(
      r'\b(quiz|exam|test|midterm|final|assignment|deadline|presentation|project|lab)\b',
      caseSensitive: false,
    );

    for (final event in upcoming) {
      if (!academicKeywords.hasMatch(event.title)) {
        continue;
      }

      final daysUntil = event.start.difference(now).inDays;
      final busyBeforeEvent = _hasBusyDayBeforeEvent(upcoming, event);
      final eventDay = DateFormat('EEEE').format(event.start);

      if (daysUntil <= 3) {
        recommendations.add(
          SmartScheduleRecommendation(
            id: 'study-${event.title.hashCode}-${event.start.millisecondsSinceEpoch}',
            type: SmartScheduleRecommendationType.study,
            title: 'Study for ${event.title}',
            message: busyBeforeEvent
                ? 'Study for ${event.title} today. Your schedule gets busy before $eventDay.'
                : 'Block a study session for ${event.title} before $eventDay.',
            reason: '${event.title} is coming up soon.',
            suggestedDate: now,
            priority: daysUntil <= 1 ? 1 : 2,
          ),
        );
      } else if (daysUntil <= 7) {
        recommendations.add(
          SmartScheduleRecommendation(
            id: 'prepare-${event.title.hashCode}-${event.start.millisecondsSinceEpoch}',
            type: SmartScheduleRecommendationType.prepare,
            title: 'Start preparing early',
            message:
                '${event.title} is on $eventDay. Start with a short prep session today.',
            reason: 'A small early session lowers last-minute pressure.',
            suggestedDate: now,
            priority: 3,
          ),
        );
      }
    }

    final busiestDay = _busiestDay(upcoming, now);
    if (busiestDay != null) {
      recommendations.add(
        SmartScheduleRecommendation(
          id: 'plan-${busiestDay.toIso8601String()}',
          type: SmartScheduleRecommendationType.plan,
          title: 'Plan around a busy day',
          message:
              '${DateFormat('EEEE').format(busiestDay)} looks packed. Move one small task earlier if you can.',
          reason: 'Your calendar has multiple events on that day.',
          suggestedDate: now,
          priority: 4,
        ),
      );
    }

    final uniqueById = <String, SmartScheduleRecommendation>{};
    for (final recommendation in recommendations) {
      uniqueById[recommendation.id] = recommendation;
    }

    return uniqueById.values.toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
  }

  bool _hasBusyDayBeforeEvent(
    List<CalendarEvent> events,
    CalendarEvent targetEvent,
  ) {
    final targetDay = DateTime(
      targetEvent.start.year,
      targetEvent.start.month,
      targetEvent.start.day,
    );

    final countsByDay = <DateTime, int>{};
    for (final event in events) {
      final day = DateTime(
        event.start.year,
        event.start.month,
        event.start.day,
      );
      if (!day.isBefore(targetDay)) {
        continue;
      }

      countsByDay[day] = (countsByDay[day] ?? 0) + 1;
    }

    return countsByDay.values.any((count) => count >= 2);
  }

  DateTime? _busiestDay(List<CalendarEvent> events, DateTime now) {
    final countsByDay = <DateTime, int>{};

    for (final event in events) {
      if (event.start.difference(now).inDays > 7) {
        continue;
      }

      final day = DateTime(
        event.start.year,
        event.start.month,
        event.start.day,
      );
      countsByDay[day] = (countsByDay[day] ?? 0) + 1;
    }

    DateTime? busiestDay;
    var busiestCount = 0;
    for (final entry in countsByDay.entries) {
      if (entry.value > busiestCount) {
        busiestDay = entry.key;
        busiestCount = entry.value;
      }
    }

    return busiestCount >= 3 ? busiestDay : null;
  }
}
