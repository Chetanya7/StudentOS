import 'package:flutter_test/flutter_test.dart';
import 'package:studentos/features/smart_scheduling/service/smart_schedule_service.dart';
import 'package:studentos/models/calendar_event.dart';

void main() {
  const service = SmartScheduleService();

  test('buildPrompt includes calendar events and JSON contract', () {
    final prompt = service.buildPrompt(
      now: DateTime(2026, 6, 13, 9),
      events: [
        CalendarEvent(title: 'Math quiz', start: DateTime(2026, 6, 15, 10)),
      ],
    );

    expect(prompt, contains('"recommendations"'));
    expect(prompt, contains('Math quiz'));
    expect(prompt, contains('JSON only'));
  });

  test('fallback recommends studying before a nearby quiz', () async {
    final recommendations = await service.getRecommendations(
      now: DateTime(2026, 6, 13, 9),
      events: [
        CalendarEvent(title: 'Morning class', start: DateTime(2026, 6, 14, 9)),
        CalendarEvent(title: 'Club meeting', start: DateTime(2026, 6, 14, 18)),
        CalendarEvent(title: 'Physics quiz', start: DateTime(2026, 6, 15, 11)),
      ],
    );

    expect(recommendations, isNotEmpty);
    expect(recommendations.first.title, contains('Physics quiz'));
    expect(recommendations.first.message, contains('today'));
  });
}
