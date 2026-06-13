import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';

import '../features/smart_scheduling/models/smart_schedule_recommendation.dart';
import '../features/smart_scheduling/service/smart_schedule_service.dart';
import '../models/calendar_event.dart';
import '../services/calendar_service.dart';

class DashboardScreen extends StatefulWidget {
  final GoogleSignInAccount user;

  const DashboardScreen({super.key, required this.user});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final CalendarService calendarService;
  late Future<List<CalendarEvent>> futureEvents;
  late Future<List<SmartScheduleRecommendation>> futureRecommendations;
  final SmartScheduleService _smartScheduleService =
      const SmartScheduleService();

  @override
  void initState() {
    super.initState();
    calendarService = CalendarService(widget.user);
    futureEvents = calendarService.getEventsForNextDays(
      days: 7,
      maxResults: 30,
    );
    futureRecommendations = futureEvents.then(
      (events) => _smartScheduleService.getRecommendations(events: events),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text("StudentOS")),
        bottomNavigationBar: Material(
          color: Theme.of(context).colorScheme.surface,
          child: const SafeArea(
            child: TabBar(
              tabs: [
                Tab(icon: Icon(Icons.event), text: 'Calendar'),
                Tab(icon: Icon(Icons.auto_awesome), text: 'Smart Schedule'),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _CalendarTab(futureEvents: futureEvents),
            _SmartScheduleTab(futureRecommendations: futureRecommendations),
          ],
        ),
      ),
    );
  }
}

class _SmartScheduleSection extends StatelessWidget {
  const _SmartScheduleSection({
    required this.isLoading,
    required this.recommendations,
  });

  final bool isLoading;
  final List<SmartScheduleRecommendation> recommendations;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Card(
        child: ListTile(
          leading: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('Planning your week'),
          subtitle: Text('Looking for useful study windows.'),
        ),
      );
    }

    if (recommendations.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.auto_awesome),
          title: Text('Smart schedule'),
          subtitle: Text('No urgent advice yet. Your week looks manageable.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 20),
            const SizedBox(width: 8),
            Text(
              'Smart schedule',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...recommendations.map(
          (recommendation) =>
              _SmartScheduleCard(recommendation: recommendation),
        ),
      ],
    );
  }
}

class _CalendarTab extends StatelessWidget {
  const _CalendarTab({required this.futureEvents});

  final Future<List<CalendarEvent>> futureEvents;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<List<CalendarEvent>>(
        future: futureEvents,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final events = snapshot.data ?? [];

          return ListView(
            children: [
              const Text(
                "Upcoming Events",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              if (events.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No calendar events this week.')),
                )
              else
                ...events.map((event) => _EventCard(event: event)),
            ],
          );
        },
      ),
    );
  }
}

class _SmartScheduleTab extends StatelessWidget {
  const _SmartScheduleTab({required this.futureRecommendations});

  final Future<List<SmartScheduleRecommendation>> futureRecommendations;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<List<SmartScheduleRecommendation>>(
        future: futureRecommendations,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          return ListView(
            children: [
              _SmartScheduleSection(
                isLoading: snapshot.connectionState == ConnectionState.waiting,
                recommendations:
                    snapshot.data ?? const <SmartScheduleRecommendation>[],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SmartScheduleCard extends StatelessWidget {
  const _SmartScheduleCard({required this.recommendation});

  final SmartScheduleRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconForType(recommendation.type)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    recommendation.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(recommendation.message),
            const SizedBox(height: 10),
            Text(
              recommendation.reason,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(SmartScheduleRecommendationType type) {
    switch (type) {
      case SmartScheduleRecommendationType.study:
        return Icons.menu_book;
      case SmartScheduleRecommendationType.prepare:
        return Icons.task_alt;
      case SmartScheduleRecommendationType.rest:
        return Icons.self_improvement;
      case SmartScheduleRecommendationType.plan:
        return Icons.event_available;
    }
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event),
        title: Text(event.title),
        subtitle: Text(
          DateFormat('EEE, dd MMM • hh:mm a').format(event.start.toLocal()),
        ),
      ),
    );
  }
}
