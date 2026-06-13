import 'package:flutter_test/flutter_test.dart';
import 'package:studentos/features/chat/service/calendar_chat_service.dart';
import 'package:studentos/models/calendar_event.dart';

void main() {
  const service = CalendarChatService();

  test('summarizeSchedule falls back when AI config is unavailable', () async {
    final summary = await service.summarizeSchedule(
      now: DateTime(2026, 6, 13, 9),
      events: [
        CalendarEvent(title: 'Physics quiz', start: DateTime(2026, 6, 15, 11)),
      ],
    );

    expect(summary, contains('academic item'));
  });

  test('answerQuestion falls back when AI config is unavailable', () async {
    final answer = await service.answerQuestion(
      question: 'When is my quiz?',
      now: DateTime(2026, 6, 13, 9),
      events: [
        CalendarEvent(title: 'Physics quiz', start: DateTime(2026, 6, 15, 11)),
      ],
      history: const [],
    );

    expect(answer, contains('could not reach the AI model'));
  });
}
