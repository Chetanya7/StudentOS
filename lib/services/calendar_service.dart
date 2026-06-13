import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart';

import '../models/calendar_event.dart';
import 'authenticated_client.dart';

class CalendarService {
  final GoogleSignInAccount user;

  CalendarService(this.user);

  Future<List<CalendarEvent>> getUpcomingEvents() async {
    try {
      final headers = await user.authHeaders;

      final client = AuthenticatedClient(headers);

      final calendarApi = CalendarApi(client);

      final now = DateTime.now();

      final events = await calendarApi.events.list(
        "primary",
        timeMin: now.toUtc(),
        maxResults: 10,
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
      print("Calendar Error: $e");

      return [];
    }
  }
}