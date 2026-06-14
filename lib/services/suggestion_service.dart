import 'package:flutter/foundation.dart';

import '../models/suggested_event.dart';

class SuggestionService {
  // In-memory suggestions store. New suggestions are added to the front.
  final List<SuggestedEvent> _items = <SuggestedEvent>[];

  /// Notifier clients can listen to to get real-time updates.
  final ValueNotifier<List<SuggestedEvent>> suggestionsNotifier =
      ValueNotifier<List<SuggestedEvent>>(<SuggestedEvent>[]);

  SuggestionService();

  Future<List<SuggestedEvent>> getSuggestions() async {
    // Simulate brief IO latency to keep API stable for callers.
    await Future.delayed(const Duration(milliseconds: 200));
    return List<SuggestedEvent>.unmodifiable(_items);
  }

  Future<void> addSuggestion(SuggestedEvent suggestion) async {
    // Avoid duplicates based on title + start time.
    final key = '${suggestion.title}-${suggestion.start.toIso8601String()}';
    final exists = _items.any((s) => '${s.title}-${s.start.toIso8601String()}' == key);
    if (!exists) {
      _items.insert(0, suggestion);
      suggestionsNotifier.value = List<SuggestedEvent>.unmodifiable(_items);
    }
  }

  Future<void> removeSuggestion(SuggestedEvent suggestion) async {
    _items.removeWhere((s) => s.title == suggestion.title && s.start == suggestion.start);
    suggestionsNotifier.value = List<SuggestedEvent>.unmodifiable(_items);
  }

  Future<void> removeSuggestionAt(int index) async {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      suggestionsNotifier.value = List<SuggestedEvent>.unmodifiable(_items);
    }
  }

  Future<void> clear() async {
    _items.clear();
    suggestionsNotifier.value = List<SuggestedEvent>.unmodifiable(_items);
  }
}