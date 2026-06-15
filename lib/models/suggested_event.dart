class SuggestedEvent {
  final String title;
  final DateTime start;
  final DateTime? end;
  final String? location;
  final String? recurrenceRule;
  final String? timeZone;
  final String source;

  SuggestedEvent({
    required this.title,
    required this.start,
    this.end,
    this.location,
    this.recurrenceRule,
    this.timeZone,
    required this.source,
  });
}
