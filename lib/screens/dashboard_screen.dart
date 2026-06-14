import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';

import '../features/chat/models/chat_message.dart';
import '../features/chat/service/calendar_chat_service.dart';
import '../features/financials/models/financial_transaction.dart';
import '../features/notification_reading/models/notification_extraction.dart';
import '../features/notification_reading/service/notification_service.dart';
import '../features/notification_reading/service/notification_ai_extraction_service.dart';
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
  final NotificationService _notificationService = NotificationService();
  final NotificationAiExtractionService _notificationAiExtractionService =
      const NotificationAiExtractionService();
  final Set<String> _alertedEventIds = <String>{};
  Timer? _pendingNotificationTimer;
  bool _isProcessingPendingNotifications = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processPendingNotificationEvents();
    });
    _pendingNotificationTimer = Timer.periodic(const Duration(seconds: 10), (
      _,
    ) {
      _processPendingNotificationEvents();
    });
  }

  @override
  void dispose() {
    _pendingNotificationTimer?.cancel();
    super.dispose();
  }

  Future<void> _processPendingNotificationEvents() async {
    if (_isProcessingPendingNotifications) return;
    _isProcessingPendingNotifications = true;

    try {
      final payloads = await _notificationService.drainPendingNotifications();
      debugPrint('Drained ${payloads.length} pending notification payload(s).');
      if (payloads.isEmpty) return;

      var createdCount = 0;
      for (final payload in payloads) {
        debugPrint(
          'Processing notification payload: ${payload.appPackageName} title="${payload.rawNotificationTitle}" text="${payload.rawNotificationText}"',
        );
        final extraction = await _notificationAiExtractionService.extract(
          payload,
        );
        debugPrint('Notification extraction result: ${extraction.toJson()}');

        if (!extraction.canCreateCalendarEvent) {
          debugPrint(
            'Notification did not become an event: ${extraction.nonEventReason ?? extraction.type.toJsonValue()}',
          );
          continue;
        }

        await calendarService.createEvent(
          title: extraction.summary ?? payload.summary ?? 'Untitled event',
          start: extraction.startDateTime!,
          end: extraction.endDateTime,
          description:
              'Created from ${payload.appLabel ?? payload.appPackageName} notification.',
          timeZone: extraction.timeZone ?? payload.timeZone,
        );
        debugPrint(
          'Created calendar event from notification: ${extraction.summary ?? payload.summary ?? 'Untitled event'}',
        );
        createdCount++;
      }

      if (!mounted || createdCount == 0) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created $createdCount calendar event(s).')),
      );

      setState(() {
        futureEvents = calendarService.getEventsForNextDays(
          days: 7,
          maxResults: 30,
        );
        futureRecommendations = futureEvents.then(
          (events) => _smartScheduleService.getRecommendations(events: events),
        );
      });
    } finally {
      _isProcessingPendingNotifications = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(title: const Text("StudentOS")),
        bottomNavigationBar: Material(
          color: Theme.of(context).colorScheme.surface,
          child: const SafeArea(
            child: TabBar(
              tabs: [
                Tab(icon: Icon(Icons.event), text: 'Calendar'),
                Tab(icon: Icon(Icons.auto_awesome), text: 'Smart Schedule'),
                Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chat'),
                Tab(icon: Icon(Icons.account_balance_wallet), text: 'Money'),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _CalendarTab(
              futureEvents: futureEvents,
              onEventsReady: _sendAcademicEventAlerts,
            ),
            _SmartScheduleTab(futureRecommendations: futureRecommendations),
            _ChatTab(futureEvents: futureEvents),
            _FinancialsTab(notificationService: _notificationService),
          ],
        ),
      ),
    );
  }

  void _sendAcademicEventAlerts(List<CalendarEvent> events) {
    final alertEvents = events.where(_shouldAlertForEvent).toList();
    if (alertEvents.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final event in alertEvents) {
        final eventId = '${event.title}-${event.start.toIso8601String()}';
        if (_alertedEventIds.contains(eventId)) {
          continue;
        }

        _alertedEventIds.add(eventId);
        _notificationService.showAcademicAlert(
          title: 'Upcoming: ${event.title}',
          message:
              '${event.title} is ${DateFormat('EEE, dd MMM • hh:mm a').format(event.start.toLocal())}.',
        );
      }
    });
  }

  bool _shouldAlertForEvent(CalendarEvent event) {
    final academicKeywords = RegExp(
      r'\b(quiz|exam|test|midterm|final|assignment|deadline|presentation|project|lab)\b',
      caseSensitive: false,
    );

    return academicKeywords.hasMatch(event.title);
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
  const _CalendarTab({required this.futureEvents, required this.onEventsReady});

  final Future<List<CalendarEvent>> futureEvents;
  final ValueChanged<List<CalendarEvent>> onEventsReady;

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
          onEventsReady(events);

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

class _ChatTab extends StatefulWidget {
  const _ChatTab({required this.futureEvents});

  final Future<List<CalendarEvent>> futureEvents;

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  final CalendarChatService _chatService = const CalendarChatService();
  final TextEditingController _questionController = TextEditingController();
  final List<ChatMessage> _messages = <ChatMessage>[];
  late Future<String> _summaryFuture;
  List<CalendarEvent> _events = const <CalendarEvent>[];
  bool _isAnswering = false;

  @override
  void initState() {
    super.initState();
    _summaryFuture = widget.futureEvents.then((events) {
      _events = events;
      return _chatService.summarizeSchedule(events: events);
    });
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _askQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty || _isAnswering) return;

    setState(() {
      _questionController.clear();
      _isAnswering = true;
      _messages.add(ChatMessage(role: ChatMessageRole.user, text: question));
    });

    final answer = await _chatService.answerQuestion(
      question: question,
      events: _events,
      history: _messages,
    );

    if (!mounted) return;

    setState(() {
      _messages.add(ChatMessage(role: ChatMessageRole.assistant, text: answer));
      _isAnswering = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: FutureBuilder<String>(
              future: _summaryFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                return ListView(
                  children: [
                    _ScheduleSummaryCard(
                      summary: snapshot.data ?? 'No summary available.',
                    ),
                    const SizedBox(height: 12),
                    if (_messages.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text('Ask anything about your schedule.'),
                        ),
                      )
                    else
                      ..._messages.map(
                        (message) => _ChatBubble(message: message),
                      ),
                    if (_isAnswering)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _questionController,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _askQuestion(),
                  decoration: const InputDecoration(
                    hintText: 'Ask about your week...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _isAnswering ? null : _askQuestion,
                icon: const Icon(Icons.send),
                tooltip: 'Send',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScheduleSummaryCard extends StatelessWidget {
  const _ScheduleSummaryCard({required this.summary});

  final String summary;

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
                const Icon(Icons.summarize),
                const SizedBox(width: 8),
                Text(
                  'Schedule summary',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(summary),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatMessageRole.user;
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(message.text),
      ),
    );
  }
}

class _FinancialsTab extends StatefulWidget {
  const _FinancialsTab({required this.notificationService});

  final NotificationService notificationService;

  @override
  State<_FinancialsTab> createState() => _FinancialsTabState();
}

class _FinancialsTabState extends State<_FinancialsTab> {
  late Future<List<FinancialTransaction>> _futureTransactions;

  @override
  void initState() {
    super.initState();
    _futureTransactions = widget.notificationService.getFinancialTransactions();
  }

  void _refresh() {
    setState(() {
      _futureTransactions = widget.notificationService
          .getFinancialTransactions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<List<FinancialTransaction>>(
        future: _futureTransactions,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final transactions = snapshot.data ?? const <FinancialTransaction>[];
          final debitTotal = transactions
              .where((transaction) => transaction.isDebit)
              .fold<double>(0, (sum, transaction) => sum + transaction.amount);
          final creditTotal = transactions
              .where((transaction) => transaction.isCredit)
              .fold<double>(0, (sum, transaction) => sum + transaction.amount);

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MoneyMetricCard(
                        label: 'Money out',
                        value: _formatMoney(debitTotal),
                        icon: Icons.arrow_upward,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MoneyMetricCard(
                        label: 'Money in',
                        value: _formatMoney(creditTotal),
                        icon: Icons.arrow_downward,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _MoneyMetricCard(
                  label: 'Net',
                  value: _formatMoney(creditTotal - debitTotal),
                  icon: Icons.account_balance_wallet,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'Recent transactions',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
                if (transactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No bank/payment notifications found yet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ...transactions.map(
                    (transaction) =>
                        _FinancialTransactionTile(transaction: transaction),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatMoney(double value) {
    final sign = value < 0 ? '-' : '';
    return '$sign₹${value.abs().toStringAsFixed(2)}';
  }
}

class _MoneyMetricCard extends StatelessWidget {
  const _MoneyMetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 8),
            Text(label),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinancialTransactionTile extends StatelessWidget {
  const _FinancialTransactionTile({required this.transaction});

  final FinancialTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final directionLabel = transaction.isDebit ? 'Spent' : 'Received';
    final amount = '₹${transaction.amount.toStringAsFixed(2)}';

    return Card(
      child: ListTile(
        leading: Icon(
          transaction.isDebit ? Icons.arrow_upward : Icons.arrow_downward,
        ),
        title: Text('$directionLabel $amount'),
        subtitle: Text(
          [
            if (transaction.sender != null && transaction.sender!.isNotEmpty)
              transaction.sender!,
            transaction.sourceApp,
            DateFormat('EEE, dd MMM • hh:mm a').format(transaction.postTime),
          ].join(' • '),
        ),
        isThreeLine: transaction.message.isNotEmpty,
        trailing: const Icon(Icons.receipt_long),
        onTap: transaction.message.isEmpty
            ? null
            : () {
                showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Transaction message'),
                    content: Text(transaction.message),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
      ),
    );
  }
}
