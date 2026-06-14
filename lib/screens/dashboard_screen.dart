import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import '../models/suggested_event.dart';
import '../services/suggestion_service.dart';

import '../features/chat/models/chat_message.dart';
import '../features/chat/service/calendar_chat_service.dart';
import '../features/financials/models/financial_transaction.dart';
import '../features/notification_reading/models/notification_extraction.dart';
import '../features/notification_reading/service/notification_service.dart';
import '../features/notification_reading/service/notification_ai_extraction_service.dart';
import '../features/notification_reading/ui/whitelist_settings_screen.dart';
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
    final SuggestionService _suggestionService = SuggestionService();
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

      // Load WhatsApp whitelists once per scan to decide which messages to send to AI.
      final peopleWhitelist = await _notificationService.getWhatsappPeopleWhitelist();
      final groupsWhitelist = await _notificationService.getWhatsappGroupsWhitelist();

      var createdCount = 0;
      for (final payload in payloads) {
        debugPrint(
          'Processing notification payload: ${payload.appPackageName} title="${payload.rawNotificationTitle}" text="${payload.rawNotificationText}"',
        );

        // If this is a WhatsApp notification, only process it if it matches
        // the configured whitelists (either a whitelisted group or a whitelisted person).
        final appId = payload.appPackageName.toLowerCase();
        final appLabel = payload.appLabel?.toLowerCase() ?? '';
        final isWhatsapp = appId.contains('whatsapp') || appLabel.contains('whatsapp');

        if (isWhatsapp) {
          var allowed = false;

          final sender = payload.senderName?.trim() ?? '';
          final conv = payload.conversationTitle?.trim() ?? '';

          // Check people whitelist. Supports group-scoped entries using 'group::person'.
          for (final entry in peopleWhitelist) {
            if (entry.contains('::')) {
              final parts = entry.split('::');
              if (parts.length >= 2) {
                final groupName = parts[0].trim();
                final personName = parts[1].trim();
                if (groupName.isNotEmpty && personName.isNotEmpty &&
                    conv.isNotEmpty && sender.isNotEmpty &&
                    groupName.toLowerCase() == conv.toLowerCase() &&
                    personName.toLowerCase() == sender.toLowerCase()) {
                  allowed = true;
                  break;
                }
              }
            } else {
              if (sender.isNotEmpty && entry.trim().toLowerCase() == sender.toLowerCase()) {
                allowed = true;
                break;
              }
            }
          }

          // Check groups whitelist if not already allowed.
          if (!allowed && conv.isNotEmpty) {
            for (final g in groupsWhitelist) {
              if (g.trim().toLowerCase() == conv.toLowerCase()) {
                allowed = true;
                break;
              }
            }
          }

          if (!allowed) {
            debugPrint('Skipping WhatsApp notification from $conv / $sender (not whitelisted).');
            continue;
          }
        }
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

          // Instead of creating the calendar event immediately, add it
          // as a suggestion so the user can accept (right-swipe) or
          // discard (left-swipe) the suggestion in the UI.
          final suggestion = SuggestedEvent(
            title: extraction.summary ?? payload.summary ?? 'Untitled event',
            start: extraction.startDateTime!,
            end: extraction.endDateTime,
            source: payload.appLabel ?? payload.appPackageName,
          );

          await _suggestionService.addSuggestion(suggestion);
          debugPrint('Added suggestion from notification: ${suggestion.title}');
          createdCount++;
      }

      if (!mounted || createdCount == 0) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $createdCount suggestion(s).')),
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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("StudentOS"),
          actions: [
            IconButton(
              tooltip: 'Notification whitelist',
              icon: const Icon(Icons.filter_alt),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WhitelistSettingsScreen(
                      notificationService: _notificationService,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        bottomNavigationBar: Material(
          color: Theme.of(context).colorScheme.surface,
          child: const SafeArea(
            child: TabBar(
              tabs: [
                Tab(icon: Icon(Icons.event), text: 'Calendar'),
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
                    onOpenSmartSchedule: _openSmartSchedule,
                    calendarService: calendarService,
                    suggestionService: _suggestionService,
                    onEventAdded: () {
                      setState(() {
                        futureEvents = calendarService.getEventsForNextDays(
                          days: 7,
                          maxResults: 30,
                        );
                        futureRecommendations = futureEvents.then(
                          (events) => _smartScheduleService.getRecommendations(events: events),
                        );
                      });
                    },
                  ),
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

  void _openSmartSchedule() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _SmartScheduleScreen(futureRecommendations: futureRecommendations),
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


class _CalendarTab extends StatefulWidget {
  const _CalendarTab({
    required this.futureEvents,
    required this.onEventsReady,
    required this.onOpenSmartSchedule,
    required this.calendarService,
    required this.suggestionService,
    this.onEventAdded,
    super.key,
  });

  final Future<List<CalendarEvent>> futureEvents;
  final ValueChanged<List<CalendarEvent>> onEventsReady;
  final VoidCallback onOpenSmartSchedule;
  final CalendarService calendarService;
  final SuggestionService suggestionService;
  final VoidCallback? onEventAdded;

  @override
  State<_CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<_CalendarTab> {
  List<SuggestedEvent> _suggestions = <SuggestedEvent>[];
  bool _showingSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
    widget.suggestionService.suggestionsNotifier.addListener(_onSuggestionsChanged);
  }

  @override
  void dispose() {
    widget.suggestionService.suggestionsNotifier.removeListener(_onSuggestionsChanged);
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    _suggestions = await widget.suggestionService.getSuggestions();
    if (!mounted) return;
    setState(() {});
  }

  void _onSuggestionsChanged() {
    if (!mounted) return;
    setState(() {
      _suggestions = widget.suggestionService.suggestionsNotifier.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<CalendarEvent>>(
          future: widget.futureEvents,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            final events = snapshot.data ?? [];
            widget.onEventsReady(events);

            return ListView(
              children: [
                // Suggestions section (first)
                _buildSuggestionsSection(),
                const SizedBox(height: 16),
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
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: widget.onOpenSmartSchedule,
        tooltip: 'Smart Schedule',
        child: const Icon(Icons.auto_awesome),
      ),
    );
  }

  Widget _buildSuggestionsSection() {
    if (_showingSuccess) {
      return Card(
        color: Colors.green.shade100,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 10),
              Text(
                "Added to Calendar",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    if (_suggestions.isEmpty) {
      return const Text('No pending suggestions');
    }

    final suggestion = _suggestions.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Pending Suggestions",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Dismissible(
          key: Key('${suggestion.title}-${suggestion.start.toIso8601String()}'),
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20),
            color: Colors.green,
            child: const Icon(Icons.check, color: Colors.white),
          ),
          secondaryBackground: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.red,
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              // Right swipe: add to calendar
              try {
                await widget.calendarService.createEvent(
                  title: suggestion.title,
                  start: suggestion.start,
                  end: suggestion.end,
                  description: 'Suggested by StudentOS: ${suggestion.source}',
                );

                if (!mounted) return;
                setState(() {
                  _showingSuccess = true;
                });

                // Remove the suggestion from the shared service; UI will update via notifier.
                await widget.suggestionService.removeSuggestion(suggestion);

                Future.delayed(const Duration(seconds: 1), () {
                  if (!mounted) return;
                  setState(() {
                    _showingSuccess = false;
                  });
                  widget.onEventAdded?.call();
                });
              } catch (e) {
                // On error, just remove suggestion and show a snackbar
                if (!mounted) return;
                await widget.suggestionService.removeSuggestion(suggestion);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to add event: $e')),
                );
              }
            } else {
              // Left swipe: discard
              if (!mounted) return;
              await widget.suggestionService.removeSuggestion(suggestion);
            }
          },
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: Text(
                suggestion.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(suggestion.source),
              trailing: Text(
                DateFormat('EEE, dd MMM • hh:mm a').format(suggestion.start.toLocal()),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SmartScheduleScreen extends StatelessWidget {
  const _SmartScheduleScreen({required this.futureRecommendations});

  final Future<List<SmartScheduleRecommendation>> futureRecommendations;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Schedule')),
      body: Padding(
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
                  isLoading:
                      snapshot.connectionState == ConnectionState.waiting,
                  recommendations:
                      snapshot.data ?? const <SmartScheduleRecommendation>[],
                ),
              ],
            );
          },
        ),
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
