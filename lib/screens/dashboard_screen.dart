import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import '../models/suggested_event.dart';
import '../services/suggestion_service.dart';
import '../services/theme_service.dart';

import '../features/chat/models/chat_message.dart';
import '../features/chat/service/calendar_chat_service.dart';
import '../features/financials/models/budget_settings.dart';
import '../features/financials/models/financial_transaction.dart';
import '../features/financials/models/private_lending_entry.dart';
import '../features/notification_reading/models/notification_extraction.dart';
import '../features/notification_reading/service/notification_service.dart';
import '../features/notification_reading/service/notification_ai_extraction_service.dart';
import 'settings_screen.dart';
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
      final peopleWhitelist = await _notificationService
          .getWhatsappPeopleWhitelist();
      final groupsWhitelist = await _notificationService
          .getWhatsappGroupsWhitelist();

      var createdCount = 0;
      for (final payload in payloads) {
        debugPrint(
          'Processing notification payload: ${payload.appPackageName} title="${payload.rawNotificationTitle}" text="${payload.rawNotificationText}"',
        );

        // If this is a WhatsApp notification, only process it if it matches
        // the configured whitelists (either a whitelisted group or a whitelisted person).
        final appId = payload.appPackageName.toLowerCase();
        final appLabel = payload.appLabel?.toLowerCase() ?? '';
        final isWhatsapp =
            appId.contains('whatsapp') || appLabel.contains('whatsapp');

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
                if (groupName.isNotEmpty &&
                    personName.isNotEmpty &&
                    conv.isNotEmpty &&
                    sender.isNotEmpty &&
                    groupName.toLowerCase() == conv.toLowerCase() &&
                    personName.toLowerCase() == sender.toLowerCase()) {
                  allowed = true;
                  break;
                }
              }
            } else {
              if (sender.isNotEmpty &&
                  entry.trim().toLowerCase() == sender.toLowerCase()) {
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
            debugPrint(
              'Skipping WhatsApp notification from $conv / $sender (not whitelisted).',
            );
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
            ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeService().themeNotifier,
              builder: (context, themeMode, child) {
                final isDark = themeMode == ThemeMode.dark ||
                    (themeMode == ThemeMode.system &&
                        MediaQuery.of(context).platformBrightness ==
                            Brightness.dark);

                return IconButton(
                  tooltip: isDark ? 'Light mode' : 'Dark mode',
                  icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                  onPressed: () {
                    ThemeService().toggleTheme();
                  },
                );
              },
            ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
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
                    (events) => _smartScheduleService.getRecommendations(
                      events: events,
                    ),
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
    widget.suggestionService.suggestionsNotifier.addListener(
      _onSuggestionsChanged,
    );
  }

  @override
  void dispose() {
    widget.suggestionService.suggestionsNotifier.removeListener(
      _onSuggestionsChanged,
    );
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
                final messenger = ScaffoldMessenger.of(context);
                await widget.suggestionService.removeSuggestion(suggestion);
                messenger.showSnackBar(
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
                DateFormat(
                  'EEE, dd MMM • hh:mm a',
                ).format(suggestion.start.toLocal()),
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
  late Future<BudgetSettings> _futureBudget;
  late Future<List<PrivateLendingEntry>> _futurePrivateLendingEntries;
  bool _showingTransactionSuccess = false;
  final Set<String> _sentRunoutAlertKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _futureTransactions = widget.notificationService.getFinancialTransactions();
    _futureBudget = widget.notificationService.getBudgetSettings();
    _futurePrivateLendingEntries = widget.notificationService
        .getPrivateLendingEntries();
  }

  void _refresh() {
    setState(() {
      _futureTransactions = widget.notificationService
          .getFinancialTransactions();
      _futureBudget = widget.notificationService.getBudgetSettings();
      _futurePrivateLendingEntries = widget.notificationService
          .getPrivateLendingEntries();
    });
  }

  Future<void> _editBudget(BudgetSettings currentBudget) async {
    final budget = await showDialog<BudgetSettings>(
      context: context,
      builder: (context) => _BudgetSettingsDialog(currentBudget: currentBudget),
    );

    if (budget == null) return;

    await widget.notificationService.setBudgetSettings(budget);
    _refresh();
  }

  Future<void> _editBalance(
    BudgetSettings currentBudget,
    double allTimeNet,
    double currentBalance,
  ) async {
    final updatedBalance = await showDialog<double>(
      context: context,
      builder: (context) => _BalanceDialog(currentBalance: currentBalance),
    );

    if (updatedBalance == null) return;

    await widget.notificationService.setBudgetSettings(
      BudgetSettings(
        budgetAmount: currentBudget.budgetAmount,
        alertAtAmount: currentBudget.alertAtAmount,
        balanceBaseAmount: updatedBalance - allTimeNet,
      ),
    );
    _refresh();
  }

  Future<void> _addManualTransaction(String direction) async {
    final transaction = await showDialog<FinancialTransaction>(
      context: context,
      builder: (context) =>
          _ManualFinancialTransactionDialog(direction: direction),
    );

    if (transaction == null) return;

    await widget.notificationService.addFinancialTransaction(transaction);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<List<Object>>(
        future: Future.wait([
          _futureTransactions,
          _futureBudget,
          _futurePrivateLendingEntries,
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final data = snapshot.data ?? const <Object>[];
          final transactions = data.isNotEmpty
              ? data[0] as List<FinancialTransaction>
              : const <FinancialTransaction>[];
          final pendingTransactions = transactions
              .where((transaction) => transaction.isPending)
              .toList();
          final budget = data.length > 1
              ? data[1] as BudgetSettings
              : const BudgetSettings(
                  budgetAmount: 0,
                  alertAtAmount: 0,
                  balanceBaseAmount: 0,
                );
          final privateLendingEntries = data.length > 2
              ? data[2] as List<PrivateLendingEntry>
              : const <PrivateLendingEntry>[];
          final countedTransactions = transactions
              .where((transaction) => !transaction.isRejected)
              .toList();
          final now = DateTime.now();
          final monthlyTransactions = countedTransactions.where((transaction) {
            return transaction.postTime.year == now.year &&
                transaction.postTime.month == now.month;
          }).toList();
          final debitTotal = monthlyTransactions
              .where((transaction) => transaction.isDebit)
              .fold<double>(0, (sum, transaction) => sum + transaction.amount);
          final creditTotal = monthlyTransactions
              .where((transaction) => transaction.isCredit)
              .fold<double>(0, (sum, transaction) => sum + transaction.amount);
          final allTimeNet = countedTransactions.fold<double>(0, (
            sum,
            transaction,
          ) {
            if (transaction.isCredit) return sum + transaction.amount;
            if (transaction.isDebit) return sum - transaction.amount;
            return sum;
          });
          final balance = budget.balanceBaseAmount + allTimeNet;
          final moneyRunout = _calculateMoneyRunout(
            balance: balance,
            monthlyDebitTotal: debitTotal,
            now: now,
          );
          final collectibleDues = _collectibleDues(privateLendingEntries);
          _sendMoneyRunoutAlert(
            runout: moneyRunout,
            collectibleDues: collectibleDues,
          );

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
                        onTap: () => _addManualTransaction('debit'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MoneyMetricCard(
                        label: 'Money in',
                        value: _formatMoney(creditTotal),
                        icon: Icons.arrow_downward,
                        onTap: () => _addManualTransaction('credit'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _MoneyMetricCard(
                  label: 'Balance',
                  value: _formatMoney(balance),
                  icon: Icons.account_balance_wallet,
                  onTap: () => _editBalance(budget, allTimeNet, balance),
                ),
                const SizedBox(height: 8),
                _BudgetCard(
                  budget: budget,
                  spent: debitTotal,
                  onTap: () => _editBudget(budget),
                ),
                if (moneyRunout != null && moneyRunout.daysLeft <= 3) ...[
                  const SizedBox(height: 8),
                  _MoneyRunoutWarningCard(
                    runout: moneyRunout,
                    collectibleDues: collectibleDues,
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _PrivateLendingScreen(
                          notificationService: widget.notificationService,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.handshake),
                  label: const Text('Private lending'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _TransactionHistoryScreen(
                          transactions: countedTransactions,
                          runout: moneyRunout,
                          collectibleDues: collectibleDues,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Transaction history'),
                ),
                const SizedBox(height: 20),
                _buildTransactionReviewSection(pendingTransactions),
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

  _MoneyRunout? _calculateMoneyRunout({
    required double balance,
    required double monthlyDebitTotal,
    required DateTime now,
  }) {
    if (balance <= 0) {
      return _MoneyRunout(
        date: now,
        daysLeft: 0,
        dailySpend: monthlyDebitTotal / now.day.clamp(1, 31),
      );
    }

    final dailySpend = monthlyDebitTotal / now.day.clamp(1, 31);
    if (dailySpend <= 0) return null;

    final daysLeft = (balance / dailySpend).floor();
    return _MoneyRunout(
      date: now.add(Duration(days: daysLeft)),
      daysLeft: daysLeft,
      dailySpend: dailySpend,
    );
  }

  double _collectibleDues(List<PrivateLendingEntry> entries) {
    final people = <String, double>{};

    for (final entry in entries) {
      final key =
          '${entry.name.trim().toLowerCase()}|${entry.phoneNumber.replaceAll(RegExp(r'\s+'), '')}';
      final delta = entry.isLent
          ? entry.amount
          : entry.isBorrowed
          ? -entry.amount
          : 0.0;
      people[key] = (people[key] ?? 0) + delta;
    }

    return people.values
        .where((amount) => amount > 0)
        .fold<double>(0, (sum, amount) => sum + amount);
  }

  void _sendMoneyRunoutAlert({
    required _MoneyRunout? runout,
    required double collectibleDues,
  }) {
    if (runout == null || runout.daysLeft < 0 || runout.daysLeft > 3) return;

    final key = DateFormat('yyyy-MM-dd').format(runout.date);
    if (_sentRunoutAlertKeys.contains(key)) return;
    _sentRunoutAlertKeys.add(key);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final runoutPhrase = runout.daysLeft == 0
          ? 'today'
          : 'in ${runout.daysLeft} day(s)';
      final collectDuesText = runout.daysLeft <= 7 && collectibleDues > 0
          ? ' You also have ₹${collectibleDues.toStringAsFixed(2)} to collect from private lending.'
          : '';
      widget.notificationService.showAcademicAlert(
        title: 'Money may run out soon',
        message:
            'At your current spending rate, your balance may run out $runoutPhrase.$collectDuesText',
      );
    });
  }

  Future<void> _reviewTransaction(
    FinancialTransaction transaction,
    String reviewStatus,
  ) async {
    await widget.notificationService.setFinancialTransactionReviewStatus(
      id: transaction.id,
      reviewStatus: reviewStatus,
    );
    if (!mounted) return;

    setState(() {
      _showingTransactionSuccess = reviewStatus == 'accepted';
    });
    _refresh();

    if (reviewStatus == 'accepted') {
      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        setState(() {
          _showingTransactionSuccess = false;
        });
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction rejected and removed from totals'),
        ),
      );
    }
  }

  Widget _buildTransactionReviewSection(
    List<FinancialTransaction> pendingTransactions,
  ) {
    if (_showingTransactionSuccess) {
      return Card(
        color: Colors.green.shade100,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 10),
              Text(
                'Transaction accepted',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    if (pendingTransactions.isEmpty) {
      return Row(
        children: [
          const Expanded(child: Text('No transactions to review right now.')),
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      );
    }

    final transaction = pendingTransactions.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Review transactions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
        ),
        const SizedBox(height: 10),
        _FinancialTransactionSuggestionCard(
          transaction: transaction,
          onEditDetails: () => _editTransactionDetails(transaction),
          onReview: (reviewStatus) =>
              _reviewTransaction(transaction, reviewStatus),
        ),
      ],
    );
  }

  Future<void> _editTransactionDetails(FinancialTransaction transaction) async {
    final details = await showDialog<_FinancialTransactionDetails>(
      context: context,
      builder: (context) => _FinancialTransactionDetailsDialog(
        initialCategory: transaction.category,
        initialDescription: transaction.description,
      ),
    );

    if (details == null) return;

    await widget.notificationService.setFinancialTransactionDetails(
      id: transaction.id,
      category: details.category,
      description: details.description,
    );
    _refresh();
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.budget,
    required this.spent,
    required this.onTap,
  });

  final BudgetSettings budget;
  final double spent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = budget.budgetAmount <= 0
        ? 0.0
        : (spent / budget.budgetAmount).clamp(0.0, 1.0);
    final isBudgetCrossed =
        budget.budgetAmount > 0 && spent >= budget.budgetAmount;
    final isAlertCrossed =
        !isBudgetCrossed &&
        budget.alertAtAmount > 0 &&
        spent >= budget.alertAtAmount;
    const overBudgetColor = Color(0xFFB3261E);
    const alertColor = Color(0xFF9A5B00);
    const overBudgetSurface = Color(0xFFFFEDEA);
    const alertSurface = Color(0xFFFFF4D8);
    final statusColor = isBudgetCrossed
        ? overBudgetColor
        : isAlertCrossed
        ? alertColor
        : null;
    final statusSurface = isBudgetCrossed
        ? overBudgetSurface
        : isAlertCrossed
        ? alertSurface
        : null;
    final colorScheme = Theme.of(context).colorScheme;
    final alertText = budget.alertAtAmount > 0
        ? 'Alert at ₹${budget.alertAtAmount.toStringAsFixed(2)}'
        : 'No alert amount set';

    return Card(
      color: statusSurface,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.savings, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Budget',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(Icons.edit, color: statusColor),
                ],
              ),
              const SizedBox(height: 10),
              if (!budget.isSet)
                const Text('Set a budget and alert amount.')
              else ...[
                Text(
                  'Spent ₹${spent.toStringAsFixed(2)} of ₹${budget.budgetAmount.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                Text(
                  isBudgetCrossed
                      ? 'Budget crossed'
                      : isAlertCrossed
                      ? 'Alert amount crossed'
                      : alertText,
                  style: TextStyle(
                    color: statusColor ?? colorScheme.onSurface,
                    fontWeight: statusColor == null
                        ? FontWeight.normal
                        : FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MoneyRunout {
  const _MoneyRunout({
    required this.date,
    required this.daysLeft,
    required this.dailySpend,
  });

  final DateTime date;
  final int daysLeft;
  final double dailySpend;
}

class _MoneyRunoutCard extends StatelessWidget {
  const _MoneyRunoutCard({required this.runout, required this.collectibleDues});

  final _MoneyRunout? runout;
  final double collectibleDues;

  @override
  Widget build(BuildContext context) {
    final title = runout == null
        ? 'Runout estimate'
        : runout!.daysLeft <= 0
        ? 'Balance may run out today'
        : 'Balance may last ${runout!.daysLeft} day(s)';
    final message = runout == null
        ? 'Add spending entries to estimate when your balance may run out.'
        : 'Expected runout: ${DateFormat('EEE, dd MMM').format(runout!.date)} based on ₹${runout!.dailySpend.toStringAsFixed(2)}/day spending.';
    final showDuesAdvice =
        runout != null && runout!.daysLeft <= 7 && collectibleDues > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hourglass_bottom),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(message),
            if (showDuesAdvice) ...[
              const SizedBox(height: 8),
              Text(
                'You have ₹${collectibleDues.toStringAsFixed(2)} to collect from private lending.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MoneyRunoutWarningCard extends StatelessWidget {
  const _MoneyRunoutWarningCard({
    required this.runout,
    required this.collectibleDues,
  });

  final _MoneyRunout runout;
  final double collectibleDues;

  @override
  Widget build(BuildContext context) {
    const warningColor = Color(0xFF9A5B00);
    const warningSurface = Color(0xFFFFF4D8);
    final warning = runout.daysLeft <= 0
        ? 'Your balance may run out today.'
        : 'Your balance may run out in ${runout.daysLeft} day(s).';

    return Card(
      color: warningSurface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber, color: warningColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                [
                  warning,
                  if (collectibleDues > 0)
                    'Collect ₹${collectibleDues.toStringAsFixed(2)} from private lending if you can.',
                ].join(' '),
                style: const TextStyle(
                  color: warningColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetSettingsDialog extends StatefulWidget {
  const _BudgetSettingsDialog({required this.currentBudget});

  final BudgetSettings currentBudget;

  @override
  State<_BudgetSettingsDialog> createState() => _BudgetSettingsDialogState();
}

class _BudgetSettingsDialogState extends State<_BudgetSettingsDialog> {
  late final TextEditingController _budgetController;
  late final TextEditingController _alertController;

  @override
  void initState() {
    super.initState();
    _budgetController = TextEditingController(
      text: widget.currentBudget.budgetAmount > 0
          ? widget.currentBudget.budgetAmount.toStringAsFixed(2)
          : '',
    );
    _alertController = TextEditingController(
      text: widget.currentBudget.alertAtAmount > 0
          ? widget.currentBudget.alertAtAmount.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _budgetController.dispose();
    _alertController.dispose();
    super.dispose();
  }

  void _submit() {
    final budget = double.tryParse(_budgetController.text.trim()) ?? 0;
    final alert = double.tryParse(_alertController.text.trim()) ?? 0;

    Navigator.pop(
      context,
      BudgetSettings(
        budgetAmount: budget,
        alertAtAmount: alert,
        balanceBaseAmount: widget.currentBudget.balanceBaseAmount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Budget settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _budgetController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Budget amount',
              prefixText: '₹',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _alertController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Notify me at',
              prefixText: '₹',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _BalanceDialog extends StatefulWidget {
  const _BalanceDialog({required this.currentBalance});

  final double currentBalance;

  @override
  State<_BalanceDialog> createState() => _BalanceDialogState();
}

class _BalanceDialogState extends State<_BalanceDialog> {
  late final TextEditingController _balanceController;

  @override
  void initState() {
    super.initState();
    _balanceController = TextEditingController(
      text: widget.currentBalance.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _balanceController.dispose();
    super.dispose();
  }

  void _submit() {
    final balance = double.tryParse(_balanceController.text.trim());
    if (balance == null) return;

    Navigator.pop(context, balance);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit balance'),
      content: TextField(
        controller: _balanceController,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: const InputDecoration(
          labelText: 'Current balance',
          prefixText: '₹',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _ManualFinancialTransactionDialog extends StatefulWidget {
  const _ManualFinancialTransactionDialog({required this.direction});

  final String direction;

  @override
  State<_ManualFinancialTransactionDialog> createState() =>
      _ManualFinancialTransactionDialogState();
}

class _ManualFinancialTransactionDialogState
    extends State<_ManualFinancialTransactionDialog> {
  static const List<String> _categories = [
    'Miscellaneous',
    'Food',
    'Transport',
    'Stationery',
    'Books',
    'Fees',
    'Hostel',
    'Rent',
    'Shopping',
    'Entertainment',
    'Health',
    'Income',
  ];

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _category = 'Miscellaneous';

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;

    final now = DateTime.now();
    final isDebit = widget.direction == 'debit';
    Navigator.pop(
      context,
      FinancialTransaction(
        id: 'manual-${now.microsecondsSinceEpoch}',
        amount: amount,
        direction: widget.direction,
        currency: 'INR',
        sourceApp: 'Manual entry',
        message: _descriptionController.text.trim(),
        postTime: now,
        reviewStatus: 'accepted',
        category: _category,
        description: _descriptionController.text.trim(),
        sender: isDebit ? 'Money out' : 'Money in',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDebit = widget.direction == 'debit';

    return AlertDialog(
      title: Text(isDebit ? 'Add money out' : 'Add money in'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: _categories
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _category = value;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description optional',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

class _PrivateLendingScreen extends StatefulWidget {
  const _PrivateLendingScreen({required this.notificationService});

  final NotificationService notificationService;

  @override
  State<_PrivateLendingScreen> createState() => _PrivateLendingScreenState();
}

class _PrivateLendingScreenState extends State<_PrivateLendingScreen> {
  late Future<List<PrivateLendingEntry>> _futureEntries;

  @override
  void initState() {
    super.initState();
    _futureEntries = widget.notificationService.getPrivateLendingEntries();
  }

  void _refresh() {
    setState(() {
      _futureEntries = widget.notificationService.getPrivateLendingEntries();
    });
  }

  Future<void> _addEntry() async {
    final entry = await showDialog<PrivateLendingEntry>(
      context: context,
      builder: (context) => const _PrivateLendingPersonDialog(),
    );

    if (entry == null) return;

    await widget.notificationService.addPrivateLendingEntry(entry);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Private Lending')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEntry,
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<PrivateLendingEntry>>(
          future: _futureEntries,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            final entries = snapshot.data ?? const <PrivateLendingEntry>[];
            final people = _peopleFromEntries(entries);
            final lent = people
                .where((person) => person.netAmount > 0)
                .fold<double>(0, (sum, person) => sum + person.netAmount);
            final borrowed = people
                .where((person) => person.netAmount < 0)
                .fold<double>(0, (sum, person) => sum + person.netAmount.abs());
            final net = lent - borrowed;

            return ListView(
              children: [
                _MoneyMetricCard(
                  label: 'Lending balance',
                  value: _formatMoney(net),
                  icon: Icons.handshake,
                ),
                const SizedBox(height: 20),
                if (people.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No private lending people yet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ...people.map(
                    (person) => _PrivateLendingPersonCard(
                      person: person,
                      onTap: () => _openPersonProfile(person, entries),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatMoney(double value) {
    final sign = value < 0 ? '-' : '';
    return '$sign₹${value.abs().toStringAsFixed(2)}';
  }

  List<_PrivateLendingPerson> _peopleFromEntries(
    List<PrivateLendingEntry> entries,
  ) {
    final people = <String, _PrivateLendingPerson>{};

    for (final entry in entries) {
      final key = _personKey(entry.name, entry.phoneNumber);
      final existing =
          people[key] ??
          _PrivateLendingPerson(
            name: entry.name,
            phoneNumber: entry.phoneNumber,
            netAmount: 0,
            latestActivity: entry.createdAt,
          );

      final netDelta = entry.isLent
          ? entry.amount
          : entry.isBorrowed
          ? -entry.amount
          : 0.0;

      people[key] = existing.copyWith(
        netAmount: existing.netAmount + netDelta,
        latestActivity: entry.createdAt.isAfter(existing.latestActivity)
            ? entry.createdAt
            : existing.latestActivity,
      );
    }

    final sorted = people.values.toList()
      ..sort((a, b) {
        final groupCompare = _sortGroup(a).compareTo(_sortGroup(b));
        if (groupCompare != 0) return groupCompare;
        return b.netAmount.abs().compareTo(a.netAmount.abs());
      });

    return sorted;
  }

  int _sortGroup(_PrivateLendingPerson person) {
    if (person.netAmount > 0) return 0;
    if (person.netAmount < 0) return 1;
    return 2;
  }

  String _personKey(String name, String phoneNumber) {
    final normalizedPhone = phoneNumber.replaceAll(RegExp(r'\s+'), '');
    return '${name.trim().toLowerCase()}|$normalizedPhone';
  }

  Future<void> _openPersonProfile(
    _PrivateLendingPerson person,
    List<PrivateLendingEntry> entries,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PrivateLendingProfileScreen(
          person: person,
          entries: entries
              .where(
                (entry) =>
                    _personKey(entry.name, entry.phoneNumber) ==
                    _personKey(person.name, person.phoneNumber),
              )
              .toList(),
          notificationService: widget.notificationService,
        ),
      ),
    );
    _refresh();
  }
}

class _PrivateLendingPerson {
  const _PrivateLendingPerson({
    required this.name,
    required this.phoneNumber,
    required this.netAmount,
    required this.latestActivity,
  });

  final String name;
  final String phoneNumber;
  final double netAmount;
  final DateTime latestActivity;

  bool get isLent => netAmount > 0;
  bool get isBorrowed => netAmount < 0;
  bool get isSettled => netAmount == 0;

  _PrivateLendingPerson copyWith({
    double? netAmount,
    DateTime? latestActivity,
  }) {
    return _PrivateLendingPerson(
      name: name,
      phoneNumber: phoneNumber,
      netAmount: netAmount ?? this.netAmount,
      latestActivity: latestActivity ?? this.latestActivity,
    );
  }
}

class _PrivateLendingPersonDialog extends StatefulWidget {
  const _PrivateLendingPersonDialog();

  @override
  State<_PrivateLendingPersonDialog> createState() =>
      _PrivateLendingPersonDialogState();
}

class _PrivateLendingPersonDialogState
    extends State<_PrivateLendingPersonDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      return;
    }

    Navigator.pop(
      context,
      PrivateLendingEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        phoneNumber: phone,
        amount: 0,
        direction: 'person',
        createdAt: DateTime.now(),
        description: '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add person'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add person')),
      ],
    );
  }
}

class _PrivateLendingProfileScreen extends StatefulWidget {
  const _PrivateLendingProfileScreen({
    required this.person,
    required this.entries,
    required this.notificationService,
  });

  final _PrivateLendingPerson person;
  final List<PrivateLendingEntry> entries;
  final NotificationService notificationService;

  @override
  State<_PrivateLendingProfileScreen> createState() =>
      _PrivateLendingProfileScreenState();
}

class _PrivateLendingProfileScreenState
    extends State<_PrivateLendingProfileScreen> {
  late List<PrivateLendingEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = List<PrivateLendingEntry>.from(widget.entries)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _addTransaction() async {
    final entry = await showDialog<PrivateLendingEntry>(
      context: context,
      builder: (context) =>
          _PrivateLendingTransactionDialog(person: widget.person),
    );

    if (entry == null) return;

    await widget.notificationService.addPrivateLendingEntry(entry);
    if (!mounted) return;

    setState(() {
      _entries = [entry, ..._entries]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  @override
  Widget build(BuildContext context) {
    final transactions = _entries.where((entry) => !entry.isPerson).toList();
    final net = transactions.fold<double>(0, (sum, entry) {
      if (entry.isLent) return sum + entry.amount;
      if (entry.isBorrowed) return sum - entry.amount;
      return sum;
    });
    final status = net > 0
        ? 'They owe you'
        : net < 0
        ? 'You owe them'
        : 'Settled';

    return Scaffold(
      appBar: AppBar(title: Text(widget.person.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTransaction,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _MoneyMetricCard(
              label: status,
              value: _formatMoney(net),
              icon: Icons.handshake,
            ),
            if (widget.person.phoneNumber.isNotEmpty) ...[
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.phone),
                title: Text(widget.person.phoneNumber),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            if (transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No lend/borrow records yet.')),
              )
            else
              ...transactions.map(
                (entry) => _PrivateLendingHistoryCard(entry: entry),
              ),
          ],
        ),
      ),
    );
  }

  String _formatMoney(double value) {
    final sign = value < 0 ? '-' : '';
    return '$sign₹${value.abs().toStringAsFixed(2)}';
  }
}

class _PrivateLendingHistoryCard extends StatelessWidget {
  const _PrivateLendingHistoryCard({required this.entry});

  final PrivateLendingEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = entry.isLent ? Colors.green : Colors.red;
    final title = entry.isLent ? 'You lent' : 'You borrowed';

    return Card(
      child: ListTile(
        leading: Icon(
          entry.isLent ? Icons.north_east : Icons.south_west,
          color: color,
        ),
        title: Text(
          '$title ₹${entry.amount.toStringAsFixed(2)}',
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            DateFormat('EEE, dd MMM • hh:mm a').format(entry.createdAt),
            if (entry.description.isNotEmpty) entry.description,
          ].join(' • '),
        ),
      ),
    );
  }
}

class _PrivateLendingTransactionDialog extends StatefulWidget {
  const _PrivateLendingTransactionDialog({required this.person});

  final _PrivateLendingPerson person;

  @override
  State<_PrivateLendingTransactionDialog> createState() =>
      _PrivateLendingTransactionDialogState();
}

class _PrivateLendingTransactionDialogState
    extends State<_PrivateLendingTransactionDialog> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _direction = 'lent';

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;

    Navigator.pop(
      context,
      PrivateLendingEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: widget.person.name,
        phoneNumber: widget.person.phoneNumber,
        amount: amount,
        direction: _direction,
        createdAt: DateTime.now(),
        description: _descriptionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.person.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'lent',
                label: Text('I lent'),
                icon: Icon(Icons.arrow_upward),
              ),
              ButtonSegment(
                value: 'borrowed',
                label: Text('I borrowed'),
                icon: Icon(Icons.arrow_downward),
              ),
            ],
            selected: {_direction},
            onSelectionChanged: (values) {
              setState(() {
                _direction = values.first;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: '₹',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Description optional',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

class _PrivateLendingPersonCard extends StatelessWidget {
  const _PrivateLendingPersonCard({required this.person, required this.onTap});

  final _PrivateLendingPerson person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amountColor = person.isLent
        ? Colors.green
        : person.isBorrowed
        ? Colors.red
        : Colors.blue;
    final label = person.isLent
        ? 'Lent'
        : person.isBorrowed
        ? 'Borrowed'
        : 'Settled';

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          person.isLent
              ? Icons.north_east
              : person.isBorrowed
              ? Icons.south_west
              : Icons.check_circle_outline,
        ),
        title: Text(person.name),
        subtitle: Text(
          [
            if (person.phoneNumber.isNotEmpty) person.phoneNumber,
            DateFormat('EEE, dd MMM • hh:mm a').format(person.latestActivity),
          ].join(' • '),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${person.netAmount.abs().toStringAsFixed(2)}',
              style: TextStyle(color: amountColor, fontWeight: FontWeight.w700),
            ),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _MoneyMetricCard extends StatelessWidget {
  const _MoneyMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(label)),
                  if (onTap != null) const Icon(Icons.edit, size: 16),
                ],
              ),
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
      ),
    );
  }
}

class _TransactionHistoryScreen extends StatefulWidget {
  const _TransactionHistoryScreen({
    required this.transactions,
    required this.runout,
    required this.collectibleDues,
  });

  final List<FinancialTransaction> transactions;
  final _MoneyRunout? runout;
  final double collectibleDues;

  @override
  State<_TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<_TransactionHistoryScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.runout != null && widget.runout!.daysLeft <= 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_runoutWarningText(widget.runout!))),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleTransactions =
        widget.transactions
            .where(
              (transaction) =>
                  !transaction.isRejected && !transaction.isPending,
            )
            .toList()
          ..sort((a, b) => b.postTime.compareTo(a.postTime));
    final spendingByCategory = <String, double>{};

    for (final transaction in visibleTransactions.where(
      (transaction) => transaction.isDebit,
    )) {
      final category = transaction.category.trim().isEmpty
          ? 'Miscellaneous'
          : transaction.category;
      spendingByCategory[category] =
          (spendingByCategory[category] ?? 0) + transaction.amount;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction History')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _MoneyRunoutCard(
              runout: widget.runout,
              collectibleDues: widget.collectibleDues,
            ),
            const SizedBox(height: 8),
            _CategorySpendingBar(spendingByCategory: spendingByCategory),
            const SizedBox(height: 20),
            const Text(
              'Transactions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            if (visibleTransactions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No accepted transactions yet.')),
              )
            else
              ...visibleTransactions.map(
                (transaction) =>
                    _TransactionHistoryCard(transaction: transaction),
              ),
          ],
        ),
      ),
    );
  }

  String _runoutWarningText(_MoneyRunout runout) {
    if (runout.daysLeft <= 0) return 'Your balance may run out today.';
    return 'Your balance may run out in ${runout.daysLeft} day(s).';
  }
}

class _CategorySpendingBar extends StatelessWidget {
  const _CategorySpendingBar({required this.spendingByCategory});

  final Map<String, double> spendingByCategory;

  static const List<Color> _colors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.brown,
    Colors.cyan,
    Colors.red,
    Colors.amber,
    Colors.grey,
  ];

  @override
  Widget build(BuildContext context) {
    final entries =
        spendingByCategory.entries.where((entry) => entry.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (sum, entry) => sum + entry.value);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.stacked_bar_chart),
                const SizedBox(width: 8),
                Text(
                  'Spending by category',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              const Text('No spending to chart yet.')
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < entries.length; index++)
                        Flexible(
                          flex: ((entries[index].value / total) * 1000)
                              .round()
                              .clamp(10, 1000),
                          fit: FlexFit.tight,
                          child: ColoredBox(
                            color: _colors[index % _colors.length],
                            child: const SizedBox.expand(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < entries.length; index++)
                    _CategoryLegendItem(
                      color: _colors[index % _colors.length],
                      label: entries[index].key,
                      amount: entries[index].value,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryLegendItem extends StatelessWidget {
  const _CategoryLegendItem({
    required this.color,
    required this.label,
    required this.amount,
  });

  final Color color;
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label ₹${amount.toStringAsFixed(2)}'),
      ],
    );
  }
}

class _TransactionHistoryCard extends StatelessWidget {
  const _TransactionHistoryCard({required this.transaction});

  final FinancialTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final isDebit = transaction.isDebit;
    final color = isDebit ? Colors.red : Colors.green;
    final title = isDebit ? 'Money out' : 'Money in';

    return Card(
      child: ListTile(
        leading: Icon(
          isDebit ? Icons.arrow_upward : Icons.arrow_downward,
          color: color,
        ),
        title: Text(
          '$title ₹${transaction.amount.toStringAsFixed(2)}',
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            transaction.category,
            if (transaction.description.isNotEmpty) transaction.description,
            transaction.sourceApp,
            DateFormat('EEE, dd MMM • hh:mm a').format(transaction.postTime),
          ].join(' • '),
        ),
        isThreeLine:
            transaction.description.isNotEmpty ||
            transaction.message.isNotEmpty,
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

class _FinancialTransactionSuggestionCard extends StatelessWidget {
  const _FinancialTransactionSuggestionCard({
    required this.transaction,
    required this.onEditDetails,
    required this.onReview,
  });

  final FinancialTransaction transaction;
  final VoidCallback onEditDetails;
  final ValueChanged<String> onReview;

  @override
  Widget build(BuildContext context) {
    final directionLabel = transaction.isDebit ? 'Spent' : 'Received';
    final amount = '₹${transaction.amount.toStringAsFixed(2)}';
    final icon = transaction.isDebit
        ? Icons.arrow_upward
        : Icons.arrow_downward;

    return Dismissible(
      key: ValueKey(transaction.id),
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
      onDismissed: (direction) {
        onReview(
          direction == DismissDirection.startToEnd ? 'accepted' : 'rejected',
        );
      },
      child: Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(
            '$directionLabel $amount',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              transaction.category,
              if (transaction.description.isNotEmpty) transaction.description,
              if (transaction.sender != null && transaction.sender!.isNotEmpty)
                transaction.sender!,
              transaction.sourceApp,
              if (transaction.message.isNotEmpty) transaction.message,
            ].join(' • '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat(
                  'EEE, dd MMM • hh:mm a',
                ).format(transaction.postTime),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              IconButton(
                onPressed: onEditDetails,
                icon: const Icon(Icons.edit_note),
                tooltip: 'Add description',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          isThreeLine: true,
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
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
          dense: false,
          minVerticalPadding: 10,
          titleAlignment: ListTileTitleAlignment.center,
          enabled: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          visualDensity: VisualDensity.standard,
        ),
      ),
    );
  }
}

class _FinancialTransactionDetails {
  const _FinancialTransactionDetails({
    required this.category,
    required this.description,
  });

  final String category;
  final String description;
}

class _FinancialTransactionDetailsDialog extends StatefulWidget {
  const _FinancialTransactionDetailsDialog({
    required this.initialCategory,
    required this.initialDescription,
  });

  final String initialCategory;
  final String initialDescription;

  @override
  State<_FinancialTransactionDetailsDialog> createState() =>
      _FinancialTransactionDetailsDialogState();
}

class _FinancialTransactionDetailsDialogState
    extends State<_FinancialTransactionDetailsDialog> {
  static const List<String> _categories = [
    'Miscellaneous',
    'Food',
    'Transport',
    'Stationery',
    'Books',
    'Fees',
    'Hostel',
    'Rent',
    'Shopping',
    'Entertainment',
    'Health',
    'Income',
  ];

  late String _category;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _category = _categories.contains(widget.initialCategory)
        ? widget.initialCategory
        : 'Miscellaneous';
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(
      context,
      _FinancialTransactionDetails(
        category: _category,
        description: _descriptionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Transaction details'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            items: _categories
                .map(
                  (category) =>
                      DropdownMenuItem(value: category, child: Text(category)),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _category = value;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Description optional',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
