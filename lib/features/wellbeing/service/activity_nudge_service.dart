import '../models/activity_models.dart';

/// Represents a nudge type for the movement nudge engine.
enum NudgeType {
  /// User is close to completing their daily goal.
  nearGoalCompletion,

  /// Long period of inactivity detected.
  inactivityReminder,

  /// Suggestion to take a walk during study breaks.
  studyBreakWalk,

  /// End-of-day movement reminder.
  endOfDayReminder,
}

/// A nudge message to display or schedule for the user.
class ActivityNudge {
  const ActivityNudge({
    required this.type,
    required this.title,
    required this.message,
    required this.priority,
  });

  final NudgeType type;
  final String title;
  final String message;

  /// Priority from 1 (highest) to 5 (lowest).
  final int priority;
}

/// Architecture for smart movement nudges.
///
/// This service provides the foundation for nudge generation.
/// Individual nudge implementations can be added incrementally
/// without modifying the core interface.
///
/// **Integration hooks for future modules:**
/// - Sleep: correlate activity with sleep quality
/// - Mood: correlate activity with mood reports
/// - Hydration: combine movement + hydration reminders
/// - Calendar: suggest walks between calendar events
abstract class ActivityNudgeProvider {
  /// Returns a nudge if conditions are met, or null otherwise.
  ActivityNudge? evaluate({
    required ActivityDashboardData data,
    required DateTime now,
  });
}

/// Near-goal completion nudge.
/// Triggers when user is within 20% of daily goal.
class NearGoalNudgeProvider implements ActivityNudgeProvider {
  const NearGoalNudgeProvider();

  @override
  ActivityNudge? evaluate({
    required ActivityDashboardData data,
    required DateTime now,
  }) {
    final steps = data.todaySteps;
    final goal = data.goal.dailyStepGoal;
    final remaining = goal - steps;

    // Only trigger if between 80-99% of goal
    if (steps >= goal) return null;
    if (remaining > goal * 0.20) return null;

    return ActivityNudge(
      type: NudgeType.nearGoalCompletion,
      title: 'Almost there!',
      message:
          'You are only ${formatStepsWithComma(remaining)} steps away from today\'s goal.',
      priority: 2,
    );
  }
}

/// End-of-day movement reminder.
/// Triggers if it's evening and user hasn't reached 50% of goal.
class EndOfDayNudgeProvider implements ActivityNudgeProvider {
  const EndOfDayNudgeProvider();

  @override
  ActivityNudge? evaluate({
    required ActivityDashboardData data,
    required DateTime now,
  }) {
    if (now.hour < 18 || now.hour > 21) return null;
    if (data.goalProgress >= 0.5) return null;

    return ActivityNudge(
      type: NudgeType.endOfDayReminder,
      title: 'Evening movement',
      message:
          'A short evening walk could boost your activity and help you sleep better tonight.',
      priority: 3,
    );
  }
}

/// Study break walk suggestion.
/// This is a placeholder for future calendar integration.
class StudyBreakNudgeProvider implements ActivityNudgeProvider {
  const StudyBreakNudgeProvider();

  @override
  ActivityNudge? evaluate({
    required ActivityDashboardData data,
    required DateTime now,
  }) {
    // Future: integrate with calendar to detect long study sessions.
    // For now, suggest a walk if activity is below 30% at midday.
    if (now.hour < 12 || now.hour > 15) return null;
    if (data.goalProgress >= 0.3) return null;

    return ActivityNudge(
      type: NudgeType.studyBreakWalk,
      title: 'Take a walk',
      message:
          'You\'ve been studying for a while. A short walk may help maintain focus.',
      priority: 4,
    );
  }
}

/// The nudge engine that evaluates all registered providers.
class ActivityNudgeEngine {
  ActivityNudgeEngine({List<ActivityNudgeProvider>? providers})
    : _providers =
          providers ??
          const [
            NearGoalNudgeProvider(),
            EndOfDayNudgeProvider(),
            StudyBreakNudgeProvider(),
          ];

  final List<ActivityNudgeProvider> _providers;

  /// Returns the highest-priority nudge available, or null.
  ActivityNudge? getTopNudge({
    required ActivityDashboardData data,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final nudges = <ActivityNudge>[];

    for (final provider in _providers) {
      final nudge = provider.evaluate(data: data, now: currentTime);
      if (nudge != null) nudges.add(nudge);
    }

    if (nudges.isEmpty) return null;
    nudges.sort((a, b) => a.priority.compareTo(b.priority));
    return nudges.first;
  }

  /// Returns all applicable nudges, sorted by priority.
  List<ActivityNudge> getAllNudges({
    required ActivityDashboardData data,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final nudges = <ActivityNudge>[];

    for (final provider in _providers) {
      final nudge = provider.evaluate(data: data, now: currentTime);
      if (nudge != null) nudges.add(nudge);
    }

    nudges.sort((a, b) => a.priority.compareTo(b.priority));
    return nudges;
  }
}
