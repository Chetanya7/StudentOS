class SuggestedEvent {
  final String title;
  final DateTime start;
  final DateTime? end;

  final String source;

  SuggestedEvent({
    required this.title,
    required this.start,
    this.end,
    required this.source,
  });
}