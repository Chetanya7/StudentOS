import '../models/notification_llm_input.dart';

class NotificationPromptBuilder {
  const NotificationPromptBuilder();

  String buildStrictExtractionPrompt(NotificationLlmInputPayload payload) {
    final String payloadJson = _prettyJson(payload.toJson());

    final lines = <String>[
      'You are an information extraction engine.',
      '',
      'Task:',
      '- Read the raw notification context.',
      '- Extract only calendar-like event information.',
      '- If the notification does not contain an event, still return valid JSON with type "other".',
      '',
      'Output rules:',
      '- Return JSON only.',
      '- Do not add markdown.',
      '- Do not add explanations.',
      '- Do not wrap the JSON in code fences.',
      '- Use the exact keys defined below.',
      '- If a field is unknown, set it to null.',
      '- If isRepeating is true, provide a repeat object.',
      '- Prefer RFC 5545 RRULE encoding in repeat.value when possible.',
      '',
      'Required JSON shape:',
      '{',
      '  "type": "event" | "other",',
      '  "startDateTime": "ISO-8601 datetime or null",',
      '  "endDateTime": "ISO-8601 datetime or null",',
      '  "isRepeating": true | false,',
      '  "repeat": {',
      '    "format": "rrule" | "cron" | "human",',
      '    "value": "string"',
      '  } | null,',
      '  "summary": "string or null",',
      '  "timeZone": "string or null"',
      '}',
      '',
      'Interpretation rules:',
      '- Treat only explicit or strongly implied event details as valid event data.',
      '- Use the notification context to infer date, time, duration, and recurrence.',
      '- If you cannot determine a field reliably, use null.',
      '- For repeating events, encode the recurrence pattern in repeat.',
      '- For one-time events, set isRepeating to false and repeat to null.',
      '',
      'Raw notification context:',
      payloadJson,
    ];

    return lines.join('\n');
  }

  String _prettyJson(Object? value, [int indentLevel = 0]) {
    const int spacesPerIndent = 2;
    final String indent = ' ' * (indentLevel * spacesPerIndent);
    final String childIndent = ' ' * ((indentLevel + 1) * spacesPerIndent);

    if (value is Map) {
      final entries = value.entries.toList();
      if (entries.isEmpty) {
        return '{}';
      }

      final buffer = StringBuffer();
      buffer.write('{\n');
      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        buffer.write(childIndent);
        buffer.write('"${_escapeString(entry.key.toString())}": ');
        buffer.write(_prettyJson(entry.value, indentLevel + 1));
        if (index != entries.length - 1) {
          buffer.write(',');
        }
        buffer.write('\n');
      }
      buffer.write('$indent}');
      return buffer.toString();
    }

    if (value is Iterable) {
      final items = value.toList();
      if (items.isEmpty) {
        return '[]';
      }

      final buffer = StringBuffer();
      buffer.write('[\n');
      for (var index = 0; index < items.length; index++) {
        buffer.write(childIndent);
        buffer.write(_prettyJson(items[index], indentLevel + 1));
        if (index != items.length - 1) {
          buffer.write(',');
        }
        buffer.write('\n');
      }
      buffer.write('$indent]');
      return buffer.toString();
    }

    if (value is String) {
      return '"${_escapeString(value)}"';
    }

    if (value == null) {
      return 'null';
    }

    return value.toString();
  }

  String _escapeString(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }
}
