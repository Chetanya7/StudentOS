class CalendarEvent {
  final String title;
  final DateTime start;
  final DateTime? end;

  CalendarEvent({required this.title, required this.start, this.end});

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'start': start.toIso8601String(),
      if (end != null) 'end': end!.toIso8601String(),
    };
  }
}
