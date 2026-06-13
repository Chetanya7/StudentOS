import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/calendar_event.dart';
import '../services/calendar_service.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends StatefulWidget {
  final GoogleSignInAccount user;

  const DashboardScreen({
    super.key,
    required this.user,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final CalendarService calendarService;
  late Future<List<CalendarEvent>> futureEvents;
  @override
  void initState() {
    super.initState();
    calendarService = CalendarService(widget.user);
    futureEvents = calendarService.getUpcomingEvents();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("StudentOS"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Welcome, ${widget.user.displayName} 👋",
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              "Upcoming Events",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: FutureBuilder<List<CalendarEvent>>(
                future: futureEvents,
                builder: (context, snapshot) {

                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                      ),
                    );
                  }

                  final events = snapshot.data ?? [];

                  return ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];

                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.event),
                          title: Text(event.title),
                          subtitle: Text(
                            DateFormat(
                              'EEE, dd MMM • hh:mm a',
                            ).format(event.start.toLocal()),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            ElevatedButton(
              onPressed: () {},
              child: const Text("Sync Calendar"),
            ),
          ],
        ),
      ),
    );
  }
}