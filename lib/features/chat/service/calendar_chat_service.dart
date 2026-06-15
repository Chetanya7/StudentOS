import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../../../models/calendar_event.dart';
import '../../../models/suggested_event.dart';
import '../../../services/hugging_face_config.dart';
import '../models/chat_data_record.dart';
import '../models/chat_message.dart';

class CalendarChatService {
  const CalendarChatService();

  static const String _fallbackTimeZone = 'Asia/Kolkata';

  Future<String> summarizeSchedule({
    required List<CalendarEvent> events,
    DateTime? now,
  }) async {
    final prompt = _buildSummaryPrompt(
      events: events,
      now: now ?? DateTime.now(),
    );
    final response = await _callHuggingFace(prompt);

    if (response != null && response.trim().isNotEmpty) {
      return _cleanText(response);
    }

    return _fallbackSummary(events);
  }

  Future<String> answerQuestion({
    required String question,
    required List<CalendarEvent> events,
    required List<ChatMessage> history,
    List<ChatDataRecord> records = const <ChatDataRecord>[],
    DateTime? now,
  }) async {
    final streams = await chooseDataStreams(
      question: question,
      events: events,
      records: records,
      history: history,
      now: now ?? DateTime.now(),
    );
    final prompt = _buildQuestionPrompt(
      question: question,
      events: events,
      records: records,
      selectedStreams: streams,
      history: history,
      now: now ?? DateTime.now(),
    );
    final response = await _callHuggingFace(prompt);

    if (response != null && response.trim().isNotEmpty) {
      return _cleanText(response);
    }

    return 'I could not reach the AI model, but I can see ${events.length} calendar events for this week.';
  }

  Future<List<ChatDataStream>> chooseDataStreams({
    required String question,
    required List<CalendarEvent> events,
    required List<ChatDataRecord> records,
    required List<ChatMessage> history,
    DateTime? now,
  }) async {
    final prompt = _buildStreamSelectionPrompt(
      question: question,
      events: events,
      records: records,
      history: history,
      now: now ?? DateTime.now(),
    );
    final response = await _callHuggingFace(prompt, maxTokens: 180);
    final selected = _parseSelectedStreams(response);

    if (selected.isNotEmpty) return selected;

    final lower = question.toLowerCase();
    final fallback = <ChatDataStream>[];
    if (RegExp(
      r'\b(schedule|calendar|class|quiz|exam|deadline|assignment)\b',
    ).hasMatch(lower)) {
      fallback.add(ChatDataStream.scheduleData);
    }
    if (RegExp(
      r'\b(money|spend|spent|budget|transaction|finance|paid|balance)\b',
    ).hasMatch(lower)) {
      fallback.add(ChatDataStream.financeData);
    }
    if (RegExp(
      r'\b(water|sleep|health|wellbeing|hydration|stress)\b',
    ).hasMatch(lower)) {
      fallback.add(ChatDataStream.wellbeingData);
    }
    if (records.isNotEmpty && fallback.isEmpty) {
      fallback.add(ChatDataStream.otherData);
    }
    return fallback;
  }

  Future<ChatDataRecord?> extractImageData({
    required Uint8List imageBytes,
    required String mimeType,
    required String userText,
    DateTime? now,
  }) async {
    final env = _loadedEnv();
    final modelUrl = env['HF_VISION_MODEL_URL']?.trim().isNotEmpty == true
        ? env['HF_VISION_MODEL_URL']!.trim()
        : env['HF_MODEL_URL']?.trim() ?? '';
    final modelId = HuggingFaceConfig.modelId(modelUrl);
    final token = env['HF_TOKEN']?.trim() ?? '';

    if (modelId == null || token.isEmpty) {
      return null;
    }

    final prompt = _buildImageExtractionPrompt(
      userText: userText,
      now: now ?? DateTime.now(),
    );
    final imageBase64 = base64Encode(imageBytes);

    try {
      final requestBody = {
        'model': '$modelId:fastest',
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:$mimeType;base64,$imageBase64'},
              },
            ],
          },
        ],
        'max_tokens': 2600,
        'temperature': 0.1,
        'stream': false,
      };
      final logBody = {
        'model': '$modelId:fastest',
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'image_url',
                'image_url': {
                  'image': 'yes',
                  'mimeType': mimeType,
                  'bytes': imageBytes.length,
                },
              },
            ],
          },
        ],
        'max_tokens': 2600,
        'temperature': 0.1,
        'stream': false,
      };
      _logLarge(
        'HF IMAGE EXTRACTION PAYLOAD',
        const JsonEncoder.withIndent('  ').convert(logBody),
      );

      final response = await http
          .post(
            HuggingFaceConfig.chatCompletionsUri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 90));

      _logLarge(
        'HF IMAGE EXTRACTION RESPONSE ${response.statusCode}',
        response.body,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Hugging Face image extraction failed: ${response.statusCode} ${response.body}',
        );
        return null;
      }

      final text = _extractGeneratedText(
        response.body,
        includeReasoningWhenPresent: true,
      );
      _logLarge('HF IMAGE EXTRACTION GENERATED TEXT', text ?? '<null>');
      if (text == null || text.trim().isEmpty) return null;
      final record = _parseImageRecord(
        text,
        userText: userText,
        now: now ?? DateTime.now(),
      );
      _logLarge(
        'HF IMAGE EXTRACTION PARSED RECORD',
        record == null
            ? '<null>'
            : const JsonEncoder.withIndent('  ').convert(record.toJson()),
      );
      return record;
    } catch (e) {
      _logLarge('HF IMAGE EXTRACTION ERROR', e.toString());
      return null;
    }
  }

  Future<List<SuggestedEvent>> extractScheduleSuggestionsFromRecord({
    required ChatDataRecord record,
    DateTime? now,
  }) async {
    if (record.stream != ChatDataStream.scheduleData) {
      return const <SuggestedEvent>[];
    }

    final prompt = _buildScheduleImageEventPrompt(
      record: record,
      now: now ?? DateTime.now(),
    );
    _logLarge('HF SCHEDULE IMAGE EVENT PAYLOAD', prompt);
    final response = await _callHuggingFace(prompt, maxTokens: 4200);
    _logLarge('HF SCHEDULE IMAGE EVENT GENERATED TEXT', response ?? '<null>');
    if (response == null || response.trim().isEmpty) {
      return const <SuggestedEvent>[];
    }

    final suggestions = _parseSuggestedEvents(
      response,
      sourceLabel: record.title,
    );
    _logLarge(
      'HF SCHEDULE IMAGE EVENT PARSED SUGGESTIONS',
      const JsonEncoder.withIndent('  ').convert(
        suggestions
            .map(
              (event) => {
                'title': event.title,
                'start': event.start.toIso8601String(),
                'end': event.end?.toIso8601String(),
                'location': event.location,
                'recurrenceRule': event.recurrenceRule,
                'timeZone': event.timeZone,
                'source': event.source,
              },
            )
            .toList(),
      ),
    );
    return suggestions;
  }

  String _buildSummaryPrompt({
    required List<CalendarEvent> events,
    required DateTime now,
  }) {
    return '''
You are StudentOS, a concise academic assistant.

Summarize the student's calendar for the week. Mention busy days, quizzes, exams, assignments, deadlines, and preparation advice. Keep it short and useful.

Current time: ${now.toIso8601String()}

Calendar events:
${const JsonEncoder.withIndent('  ').convert(events.map((event) => event.toJson()).toList())}

Return only the summary text. Do not return JSON.
''';
  }

  String _buildQuestionPrompt({
    required String question,
    required List<CalendarEvent> events,
    required List<ChatDataRecord> records,
    required List<ChatDataStream> selectedStreams,
    required List<ChatMessage> history,
    required DateTime now,
  }) {
    final recentHistory = history
        .take(8)
        .map(
          (message) => {
            'role': message.role == ChatMessageRole.user ? 'user' : 'assistant',
            'text': message.text,
          },
        )
        .toList();

    final selectedStreamValues = selectedStreams
        .map((stream) => stream.value)
        .toSet();
    final selectedRecords = records
        .where((record) => selectedStreamValues.contains(record.stream.value))
        .map((record) => record.toJson())
        .toList();
    final includeSchedule =
        selectedStreams.contains(ChatDataStream.scheduleData) ||
        selectedStreams.isEmpty;

    final payload = {
      'now': now.toIso8601String(),
      'availableDataCategories': [
        'schedule_data',
        'finance_data',
        'wellbeing_data',
        'other_data',
      ],
      'selectedDataStreams': selectedStreams
          .map((stream) => stream.value)
          .toList(),
      'calendarEvents': includeSchedule
          ? events.map((event) => event.toJson()).toList()
          : const <Map<String, dynamic>>[],
      'uploadedImageRecords': selectedRecords,
      'recentChatHistory': recentHistory,
      'question': question,
    };

    return '''
You are StudentOS, a helpful academic assistant.

Answer the student's question using only the selected data provided. If useful data is missing, say what is missing and give a practical next step.

Keep the answer concise and practical.

Payload:
${const JsonEncoder.withIndent('  ').convert(payload)}

Return only the answer text. Do not return JSON.
''';
  }

  String _buildStreamSelectionPrompt({
    required String question,
    required List<CalendarEvent> events,
    required List<ChatDataRecord> records,
    required List<ChatMessage> history,
    required DateTime now,
  }) {
    final available = {
      'schedule_data': {
        'description': 'calendar, classes, exams, quizzes, deadlines',
        'count': events.length,
      },
      'finance_data': {
        'description': 'money, transactions, budget, lending, payments',
        'count': records
            .where((record) => record.stream == ChatDataStream.financeData)
            .length,
      },
      'wellbeing_data': {
        'description': 'hydration, sleep, health, habits, wellbeing',
        'count': records
            .where((record) => record.stream == ChatDataStream.wellbeingData)
            .length,
      },
      'other_data': {
        'description':
            'uploaded image/document data outside the main categories',
        'count': records
            .where((record) => record.stream == ChatDataStream.otherData)
            .length,
        'subcategories': records
            .where((record) => record.stream == ChatDataStream.otherData)
            .map((record) => record.subcategory)
            .toSet()
            .toList(),
      },
    };

    return '''
You are the StudentOS chat router.

Choose which data streams are needed to answer the user. Available streams:
- schedule_data
- finance_data
- wellbeing_data
- other_data

Return only JSON:
{"streams":["schedule_data"],"can_answer_directly":false,"direct_answer":null}

If no data is needed, return streams [] and put a concise direct answer in direct_answer.

Current time: ${now.toIso8601String()}
Question: $question
Available data:
${const JsonEncoder.withIndent('  ').convert(available)}
Recent chat:
${const JsonEncoder.withIndent('  ').convert(history.take(6).map((message) => {'role': message.role.name, 'text': message.text}).toList())}
''';
  }

  String _buildImageExtractionPrompt({
    required String userText,
    required DateTime now,
  }) {
    return '''
You are StudentOS image ingestion. Extract useful student data from the uploaded image and optional user message.

Do not explain your reasoning. Do not write analysis. Return the final JSON in the assistant content only.

Classify the result into exactly one stream:
- schedule_data: timetable, calendar event, deadline, quiz, exam, assignment
- finance_data: receipt, bill, fee, payment, transaction, budget
- wellbeing_data: health, hydration, sleep, medicine, fitness, habit
- other_data: anything else

For other_data, create a short lowercase subcategory like "lab_manual", "poster", "notes", "id_card", "menu", "general".

If stream is schedule_data and the image is a timetable:
- extractedText must include every visible class/lab slot as separate lines.
- Each line should include day, start time, end time, class/course label, and room/location if visible.
- Do not only return the course legend or faculty list.
- People/faculty are optional and less important than day/time/class/location slots.

Return only JSON:
{
  "stream": "schedule_data|finance_data|wellbeing_data|other_data",
  "subcategory": "short_subcategory",
  "title": "short title",
  "summary": "1-3 sentence useful summary",
  "extractedText": "for timetables, all visible day/time/class/location slot lines; otherwise compact important text extracted from image",
  "structuredData": {
    "dates": [],
    "amounts": [],
    "tasks": [],
    "people": [],
    "locations": [],
    "scheduleSlots": [
      {
        "day": "Monday",
        "startTime": "09:00",
        "endTime": "10:00",
        "title": "OS",
        "location": "AB5-206"
      }
    ]
  }
}

Current time: ${now.toIso8601String()}
Optional user message: ${userText.isEmpty ? '(none)' : userText}
''';
  }

  String _buildScheduleImageEventPrompt({
    required ChatDataRecord record,
    required DateTime now,
  }) {
    return '''
You are StudentOS schedule extraction.

The image has already been OCR/extracted into text and classified as schedule_data. Convert it into calendar suggestion events.

Rules:
- Return 0 to 40 events.
- For a weekly timetable, create one event per recurring class/lab slot.
- For weekly timetable slots, set isRepeating true and recurrenceRule to an RFC 5545 weekly RRULE like "RRULE:FREQ=WEEKLY;BYDAY=MO".
- For recurring events, set timeZone to "$_fallbackTimeZone".
- Resolve day names relative to current date by choosing the next occurrence of that weekday.
- Use the extracted timetable text from the image record as the source of truth.
- If the image record contains course codes, subject names, days, and time ranges, create suggestions from those.
- Ignore faculty/people names when creating events.
- Put room/building/lab in location, never in title.
- If a class cell contains a parenthesized room like "(CL-5)", title should omit it and location should be "CL-5".
- Title must be only the class/course label from the timetable cell, for example "OS", "DAA", "DBS", "PAO", "IAI", "DBSL-4CCE-A1", or "OSL-4CCE-A2".
- Title must not include weekday, time, faculty, room, location, recurrence, or phrases like "Class".
- If exact date is present, use it.
- If end time is missing, infer a reasonable 1 hour duration.
- Use null only when the event is too ambiguous.
- Do not invent classes that are not present.
- If the input clearly contains a timetable, do not return an empty events list.
- Return compact minified JSON. Do not use markdown fences.
- Do not include long source strings; use short values like "timetable".

Return only JSON:
{
  "events": [
    {
      "title": "Course or event title",
      "startDateTime": "ISO-8601 datetime",
      "endDateTime": "ISO-8601 datetime",
      "isRepeating": true,
      "recurrenceRule": "RRULE:FREQ=WEEKLY;BYDAY=MO",
      "timeZone": "$_fallbackTimeZone",
      "location": "room or null",
      "source": "short reason"
    }
  ]
}

Current time: ${now.toIso8601String()}
Image record:
${const JsonEncoder.withIndent('  ').convert(record.toJson())}
''';
  }

  Future<String?> _callHuggingFace(String prompt, {int maxTokens = 500}) async {
    final env = _loadedEnv();
    final modelUrl = env['HF_MODEL_URL']?.trim() ?? '';
    final modelId = HuggingFaceConfig.modelId(modelUrl);
    final token = env['HF_TOKEN']?.trim() ?? '';

    if (modelId == null || token.isEmpty) {
      return null;
    }

    try {
      final requestBody = {
        'model': '$modelId:fastest',
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'max_tokens': maxTokens,
        'temperature': 0.3,
        'stream': false,
      };
      _logLarge(
        'HF CHAT PAYLOAD',
        const JsonEncoder.withIndent('  ').convert(requestBody),
      );

      final response = await http
          .post(
            HuggingFaceConfig.chatCompletionsUri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 25));

      _logLarge('HF CHAT RESPONSE ${response.statusCode}', response.body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Hugging Face chat failed: ${response.statusCode} ${response.body}',
        );
        return null;
      }

      return _extractGeneratedText(response.body);
    } catch (e) {
      debugPrint('Hugging Face chat error: $e');
      return null;
    }
  }

  List<ChatDataStream> _parseSelectedStreams(String? source) {
    if (source == null || source.trim().isEmpty) {
      return const <ChatDataStream>[];
    }
    final jsonText = _extractJsonObject(source);
    if (jsonText == null) return const <ChatDataStream>[];

    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map || decoded['streams'] is! List) {
        return const <ChatDataStream>[];
      }
      return (decoded['streams'] as List)
          .map((value) => ChatDataStreamJson.fromValue(value?.toString()))
          .toSet()
          .toList();
    } catch (_) {
      return const <ChatDataStream>[];
    }
  }

  ChatDataRecord? _parseImageRecord(
    String source, {
    required String userText,
    required DateTime now,
  }) {
    final jsonText = _extractJsonObject(source);
    if (jsonText == null) {
      final inferredStream = _inferImageStream(source, userText);
      final cleanSource = _cleanText(source);
      return ChatDataRecord(
        id: 'image-${now.microsecondsSinceEpoch}',
        stream: inferredStream,
        subcategory: inferredStream == ChatDataStream.scheduleData
            ? 'timetable'
            : 'image',
        title: inferredStream == ChatDataStream.scheduleData
            ? 'Uploaded schedule'
            : userText.isEmpty
            ? 'Uploaded image'
            : userText,
        summary: inferredStream == ChatDataStream.scheduleData
            ? 'Extracted schedule information from the uploaded image.'
            : cleanSource,
        extractedText: cleanSource,
        createdAt: now,
      );
    }

    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) return null;
      final map = decoded.cast<String, dynamic>();
      _logLarge(
        'HF IMAGE EXTRACTION JSON OBJECT',
        const JsonEncoder.withIndent('  ').convert(map),
      );
      final combinedSource = [
        source,
        map['title'],
        map['summary'],
        map['subcategory'],
        map['extractedText'],
        if (map['structuredData'] != null)
          const JsonEncoder.withIndent('  ').convert(map['structuredData']),
      ].whereType<Object>().map((value) => value.toString()).join('\n');
      final inferredStream = _normalizeImageStream(
        map['stream']?.toString(),
        combinedSource,
        userText,
      );
      final extractedText = _bestExtractedText(
        map,
        source,
        includeSource: inferredStream == ChatDataStream.scheduleData,
      );
      return ChatDataRecord(
        id: 'image-${now.microsecondsSinceEpoch}',
        stream: inferredStream,
        subcategory:
            map['subcategory']?.toString() ??
            (inferredStream == ChatDataStream.scheduleData
                ? 'timetable'
                : 'general'),
        title: map['title']?.toString() ?? 'Uploaded image',
        summary: map['summary']?.toString() ?? '',
        extractedText: extractedText,
        createdAt: now,
        structuredData: map['structuredData'] is Map
            ? Map<String, dynamic>.from(map['structuredData'] as Map)
            : const <String, dynamic>{},
      );
    } catch (e) {
      debugPrint('Image record parse failed: $e');
      _logLarge('HF IMAGE RECORD PARSE SOURCE', source);
      final inferredStream = _inferImageStream(source, userText);
      return ChatDataRecord(
        id: 'image-${now.microsecondsSinceEpoch}',
        stream: inferredStream,
        subcategory: inferredStream == ChatDataStream.scheduleData
            ? 'timetable'
            : 'image',
        title: inferredStream == ChatDataStream.scheduleData
            ? 'Uploaded schedule'
            : userText.isEmpty
            ? 'Uploaded image'
            : userText,
        summary: inferredStream == ChatDataStream.scheduleData
            ? 'Extracted schedule information from the uploaded image.'
            : _cleanText(source),
        extractedText: _cleanText(source),
        createdAt: now,
      );
    }
  }

  ChatDataStream _normalizeImageStream(
    String? rawStream,
    String source,
    String userText,
  ) {
    final inferred = _inferImageStream(source, userText);
    if (inferred == ChatDataStream.scheduleData) {
      return inferred;
    }

    final value = rawStream?.trim();
    if (value == 'schedule_data' ||
        value == 'finance_data' ||
        value == 'wellbeing_data' ||
        value == 'other_data') {
      return ChatDataStreamJson.fromValue(value);
    }
    return _inferImageStream(source, userText);
  }

  ChatDataStream _inferImageStream(String source, String userText) {
    final lower = '$source\n$userText'.toLowerCase();
    if (RegExp(
      r'\b(timetable|time table|schedule|class|classes|course|semester|lecture|lab|room)\b|\b(mon|monday|tue|tues|tuesday|wed|wednesday|thu|thur|thurs|thursday|fri|friday|sat|saturday)\b.*\b\d{1,2}[.:]\d{2}\b|\b\d{1,2}[.:]\d{2}\s*[-–—to]+\s*\d{1,2}[.:]\d{2}\b.*\b(class|lab|lecture|course|os|dbs|daa|iai|pao)\b',
    ).hasMatch(lower)) {
      return ChatDataStream.scheduleData;
    }
    if (RegExp(
      r'\b(receipt|paid|payment|transaction|amount|invoice|bill|upi|rs\.?|inr|₹)\b',
    ).hasMatch(lower)) {
      return ChatDataStream.financeData;
    }
    if (RegExp(
      r'\b(water|hydration|sleep|medicine|health|workout|calorie|diet)\b',
    ).hasMatch(lower)) {
      return ChatDataStream.wellbeingData;
    }
    return ChatDataStream.otherData;
  }

  String _bestExtractedText(
    Map<String, dynamic> map,
    String source, {
    bool includeSource = false,
  }) {
    final extracted = map['extractedText']?.toString().trim() ?? '';
    if (extracted.isNotEmpty && !includeSource) {
      return extracted;
    }

    final parts = <String>[
      extracted,
      map['title']?.toString() ?? '',
      map['summary']?.toString() ?? '',
      if (map['structuredData'] != null)
        const JsonEncoder.withIndent('  ').convert(map['structuredData']),
      if (includeSource) source,
    ].where((part) => part.trim().isNotEmpty).toList();
    return _cleanText(parts.join('\n\n'));
  }

  List<SuggestedEvent> _parseSuggestedEvents(
    String responseText, {
    required String sourceLabel,
  }) {
    final jsonText = _extractJsonObject(responseText);
    if (jsonText == null) {
      return _parseSuggestedEventsFromPartialJson(
        responseText,
        sourceLabel: sourceLabel,
      );
    }

    try {
      final decoded = jsonDecode(jsonText);
      _logLarge('HF SCHEDULE EVENT JSON OBJECT', jsonText);
      final rawEvents = decoded is Map
          ? decoded['events']
          : decoded is List
          ? decoded
          : null;
      if (rawEvents is! List) {
        return _parseSuggestedEventsFromPartialJson(
          responseText,
          sourceLabel: sourceLabel,
        );
      }

      return rawEvents
          .whereType<Map>()
          .map(
            (value) => _suggestedEventFromMap(
              value.cast<String, dynamic>(),
              sourceLabel: sourceLabel,
            ),
          )
          .whereType<SuggestedEvent>()
          .toList();
    } catch (e) {
      debugPrint('Schedule suggestion parse failed: $e');
      _logLarge('HF SCHEDULE EVENT PARSE SOURCE', responseText);
      return _parseSuggestedEventsFromPartialJson(
        responseText,
        sourceLabel: sourceLabel,
      );
    }
  }

  List<SuggestedEvent> _parseSuggestedEventsFromPartialJson(
    String responseText, {
    required String sourceLabel,
  }) {
    final eventMatches = RegExp(
      r'\{[^{}]*"title"\s*:\s*"[^"]+"[^{}]*"startDateTime"\s*:\s*"[^"]+"[^{}]*\}',
      dotAll: true,
    ).allMatches(responseText);

    final events = <SuggestedEvent>[];
    for (final match in eventMatches) {
      try {
        final decoded = jsonDecode(match.group(0)!);
        if (decoded is! Map) continue;
        final event = _suggestedEventFromMap(
          decoded.cast<String, dynamic>(),
          sourceLabel: sourceLabel,
        );
        if (event != null) events.add(event);
      } catch (_) {
        continue;
      }
    }

    if (events.isNotEmpty) {
      _logLarge(
        'HF SCHEDULE EVENT PARTIAL JSON RECOVERY',
        'Recovered ${events.length} complete event object(s) from truncated JSON.',
      );
    }
    return events;
  }

  SuggestedEvent? _suggestedEventFromMap(
    Map<String, dynamic> map, {
    required String sourceLabel,
  }) {
    var start = DateTime.tryParse(map['startDateTime']?.toString() ?? '');
    if (start == null) return null;
    var end = DateTime.tryParse(map['endDateTime']?.toString() ?? '');
    final rawTitle = map['title']?.toString();
    final title = _cleanSuggestedTitle(rawTitle);
    final location =
        _cleanOptionalString(map['location']) ?? _locationFromTitle(rawTitle);
    final recurrenceRule = _normalizeRecurrenceRule(map, start);
    if (recurrenceRule != null) {
      final adjusted = _alignDateToRecurrenceDay(start, end, recurrenceRule);
      start = adjusted.$1;
      end = adjusted.$2;
    }
    final timeZone =
        _cleanOptionalString(map['timeZone']) ??
        (recurrenceRule == null ? null : _fallbackTimeZone);
    return SuggestedEvent(
      title: title.isEmpty ? 'Schedule event' : title,
      start: start,
      end: end,
      location: location,
      recurrenceRule: recurrenceRule,
      timeZone: timeZone,
      source: sourceLabel,
    );
  }

  String _cleanSuggestedTitle(String? rawTitle) {
    var title = rawTitle?.trim() ?? '';
    if (title.isEmpty) return '';

    title = title
        .replaceAll(
          RegExp(r'\s*\([^)]*weekly[^)]*\)', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\s*\([^)]*repeats?[^)]*\)', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\s*\((?:CL|ROOM|AB|LAB)[^)]+\)', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\s*[-–—]\s*(weekly|repeats?).*$', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'\s*\b(?:mon|tue|wed|thu|fri|sat|sun)(?:day)?\b.*$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s*\b\d{1,2}[.:]\d{2}\b.*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return title;
  }

  String? _locationFromTitle(String? rawTitle) {
    final match = RegExp(
      r'\((CL-[^)]+|ROOM\s*[^)]+|AB[^)]+|LAB\s*[^)]+)\)',
      caseSensitive: false,
    ).firstMatch(rawTitle ?? '');
    return match?.group(1)?.trim();
  }

  String? _cleanOptionalString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }
    return text;
  }

  String? _normalizeRecurrenceRule(Map<String, dynamic> map, DateTime start) {
    final explicit = _cleanOptionalString(map['recurrenceRule']);
    if (explicit != null) {
      return explicit.toUpperCase().startsWith('RRULE:')
          ? explicit
          : 'RRULE:$explicit';
    }

    final repeat = map['repeat'];
    String? repeatValue;
    if (repeat is Map) {
      repeatValue = _cleanOptionalString(repeat['value']);
    } else {
      repeatValue = _cleanOptionalString(repeat);
    }

    if (repeatValue == null) {
      return map['isRepeating'] == true
          ? 'RRULE:FREQ=WEEKLY;BYDAY=${_byDayForDate(start)}'
          : null;
    }

    if (repeatValue.toUpperCase().startsWith('RRULE:')) {
      return repeatValue;
    }

    final byDay = _byDayFromText(repeatValue) ?? _byDayForDate(start);
    if (repeatValue.toLowerCase().contains('weekly') ||
        map['isRepeating'] == true) {
      return 'RRULE:FREQ=WEEKLY;BYDAY=$byDay';
    }

    return null;
  }

  (DateTime, DateTime?) _alignDateToRecurrenceDay(
    DateTime start,
    DateTime? end,
    String recurrenceRule,
  ) {
    final byDay = RegExp(r'BYDAY=([A-Z]{2})').firstMatch(recurrenceRule);
    if (byDay == null) return (start, end);

    final targetWeekday = _weekdayFromByDay(byDay.group(1)!);
    if (targetWeekday == null || start.weekday == targetWeekday) {
      return (start, end);
    }

    final daysForward = (targetWeekday - start.weekday + 7) % 7;
    final adjustedStart = start.add(Duration(days: daysForward));
    final adjustedEnd = end?.add(Duration(days: daysForward));
    return (adjustedStart, adjustedEnd);
  }

  int? _weekdayFromByDay(String byDay) {
    switch (byDay) {
      case 'MO':
        return DateTime.monday;
      case 'TU':
        return DateTime.tuesday;
      case 'WE':
        return DateTime.wednesday;
      case 'TH':
        return DateTime.thursday;
      case 'FR':
        return DateTime.friday;
      case 'SA':
        return DateTime.saturday;
      case 'SU':
        return DateTime.sunday;
      default:
        return null;
    }
  }

  String? _byDayFromText(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('monday')) return 'MO';
    if (lower.contains('tuesday')) return 'TU';
    if (lower.contains('wednesday')) return 'WE';
    if (lower.contains('thursday')) return 'TH';
    if (lower.contains('friday')) return 'FR';
    if (lower.contains('saturday')) return 'SA';
    if (lower.contains('sunday')) return 'SU';
    return null;
  }

  String _byDayForDate(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'MO';
      case DateTime.tuesday:
        return 'TU';
      case DateTime.wednesday:
        return 'WE';
      case DateTime.thursday:
        return 'TH';
      case DateTime.friday:
        return 'FR';
      case DateTime.saturday:
        return 'SA';
      case DateTime.sunday:
      default:
        return 'SU';
    }
  }

  String? _extractJsonObject(String source) {
    final fenced = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      caseSensitive: false,
    ).firstMatch(source);
    final text = fenced?.group(1) ?? source;
    final trimmedLeft = text.trimLeft();
    final leadingOffset = text.length - trimmedLeft.length;
    final start = trimmedLeft.startsWith('{')
        ? leadingOffset
        : trimmedLeft.startsWith('[')
        ? leadingOffset
        : text.contains('{')
        ? text.indexOf('{')
        : text.indexOf('[');
    if (start == -1) return null;

    var depth = 0;
    final opening = text[start];
    final closing = opening == '{' ? '}' : ']';
    var inString = false;
    var escaping = false;
    for (var index = start; index < text.length; index++) {
      final char = text[index];
      if (escaping) {
        escaping = false;
        continue;
      }
      if (char == '\\') {
        escaping = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (char == opening) {
        depth++;
      } else if (char == closing) {
        depth--;
        if (depth == 0) {
          return text.substring(start, index + 1);
        }
      }
    }

    return null;
  }

  void _logLarge(String title, String message) {
    const chunkSize = 900;
    debugPrint('===== $title START =====');
    if (message.isEmpty) {
      debugPrint('<empty>');
    } else {
      for (var index = 0; index < message.length; index += chunkSize) {
        final end = (index + chunkSize).clamp(0, message.length);
        debugPrint(message.substring(index, end));
      }
    }
    debugPrint('===== $title END =====');
  }

  Map<String, String> _loadedEnv() {
    try {
      return dotenv.env;
    } catch (_) {
      return const {};
    }
  }

  String? _extractGeneratedText(
    String responseBody, {
    bool includeReasoningWhenPresent = false,
  }) {
    final decoded = jsonDecode(responseBody);

    if (decoded is Map) {
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map) {
          final message = first['message'];
          if (message is Map) {
            final content = message['content']?.toString() ?? '';
            final reasoning = message['reasoning']?.toString() ?? '';
            if (content.trim().isNotEmpty) {
              if (includeReasoningWhenPresent && reasoning.trim().isNotEmpty) {
                return '$content\n\nAdditional extraction notes:\n$reasoning';
              }
              return content;
            }

            if (reasoning.trim().isNotEmpty) {
              return reasoning;
            }
          }
        }
      }
    }

    if (decoded is List && decoded.isNotEmpty) {
      final first = decoded.first;
      if (first is Map && first['generated_text'] != null) {
        return first['generated_text'].toString();
      }
    }

    if (decoded is Map) {
      if (decoded['generated_text'] != null) {
        return decoded['generated_text'].toString();
      }

      if (decoded['error'] != null) {
        debugPrint('Hugging Face chat error: ${decoded['error']}');
      }
    }

    return null;
  }

  String _cleanText(String text) {
    return text.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  String _fallbackSummary(List<CalendarEvent> events) {
    if (events.isEmpty) {
      return 'Your calendar is clear for the week.';
    }

    final academicEvents = events.where((event) {
      return RegExp(
        r'\b(quiz|exam|test|midterm|final|assignment|deadline|presentation|project|lab)\b',
        caseSensitive: false,
      ).hasMatch(event.title);
    }).toList();

    if (academicEvents.isEmpty) {
      return 'You have ${events.length} events this week and no obvious quizzes, assignments, or deadlines on the calendar.';
    }

    return 'You have ${events.length} events this week, including ${academicEvents.length} academic item(s) that may need prep.';
  }
}
