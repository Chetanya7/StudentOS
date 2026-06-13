import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart';

import '../models/calendar_event.dart';
import 'authenticated_client.dart';

class CalendarService {
  final GoogleSignInAccount user;

  CalendarService(this.user);

  Future<List<CalendarEvent>> getUpcomingEvents() async {
    return getEventsForNextDays(days: 7, maxResults: 20);
  }

  Future<List<CalendarEvent>> getEventsForNextDays({
    int days = 7,
    int maxResults = 20,
  }) async {
    try {
      final headers = await user.authHeaders;

      final client = AuthenticatedClient(headers);

      final calendarApi = CalendarApi(client);

      final now = DateTime.now();

      final events = await calendarApi.events.list(
        "primary",
        timeMin: now.toUtc(),
        timeMax: now.add(Duration(days: days)).toUtc(),
        maxResults: maxResults,
        singleEvents: true,
        orderBy: "startTime",
      );

      return events.items
              ?.where((e) => e.start?.dateTime != null)
              .map(
                (e) => CalendarEvent(
                  title: e.summary ?? "Untitled Event",
                  start: e.start!.dateTime!,
                  end: e.end?.dateTime,
                ),
              )
              .toList() ??
          [];
    } catch (e) {
      debugPrint("Calendar Error: $e");

      return [];
    }
  }

  Future<void> createEvent({
    required String title,
    required DateTime start,
    DateTime? end,
    String? description,
    String? timeZone,
  }) async {
    final headers = await user.authHeaders;
    final client = AuthenticatedClient(headers);
    final calendarApi = CalendarApi(client);

    final event = Event(
      summary: title,
      description: description,
      start: EventDateTime(dateTime: start, timeZone: timeZone),
      end: EventDateTime(
        dateTime: end ?? start.add(const Duration(hours: 1)),
        timeZone: timeZone,
      ),
    );

    await calendarApi.events.insert(event, "primary");
  }
}
