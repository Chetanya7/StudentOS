from __future__ import annotations

import json
from typing import Any


def notification_extraction_prompt(payload: dict[str, Any]) -> str:
    return f"""
You are an information extraction engine.

Task:
- Read the raw notification context.
- Extract only calendar-like event information.
- If the notification does not contain an event, still return valid JSON with type "other".

Output rules:
- Return JSON only.
- Do not add markdown.
- Do not add explanations.
- Do not wrap the JSON in code fences.
- Use the exact keys defined below.
- If a field is unknown, set it to null.
- If type is "other", set all event-specific fields to null and explain in nonEventReason.
- For event notifications, resolve relative dates into concrete ISO-8601 datetimes when currentDate/currentDateTime is provided.
- If isRepeating is true, provide a repeat object.
- Prefer RFC 5545 RRULE encoding in repeat.value when possible.

Required JSON shape:
{{
  "type": "event" | "other",
  "startDateTime": "ISO-8601 datetime or null",
  "endDateTime": "ISO-8601 datetime or null",
  "isRepeating": true | false,
  "repeat": {{
    "format": "rrule" | "cron" | "human",
    "value": "string"
  }} | null,
  "summary": "string or null",
  "timeZone": "string or null",
  "nonEventReason": "string or null"
}}

Raw notification context:
{json.dumps(payload, indent=2)}
""".strip()


def smart_schedule_prompt(now: str, timezone: str | None, calendar_events: list[dict[str, Any]]) -> str:
    payload = {
        "now": now,
        "timezone": timezone,
        "calendarEvents": calendar_events,
    }
    return f"""
Given this week's calendar events, return JSON only. Recommend small, actionable scheduling advice for a student.
Prefer advice that anticipates upcoming academic deadlines, quizzes, exams, assignments, project meetings, presentations, and busy days.

Rules:
- Return 0 to 5 recommendations.
- Each recommendation should be useful today or in the next few days.
- If a quiz/exam/deadline is soon and the student is busy before it, recommend studying earlier.
- Do not invent calendar events.
- Keep messages short enough for a phone notification.

Return this exact shape:
{{
  "recommendations": [
    {{
      "id": "stable-short-id",
      "type": "study|prepare|rest|plan",
      "title": "short title",
      "message": "student-facing advice",
      "reason": "why this advice follows from the calendar",
      "suggestedDate": "ISO-8601 datetime",
      "priority": 1
    }}
  ]
}}

Calendar payload:
{json.dumps(payload, indent=2)}
""".strip()


def schedule_suggestions_prompt(record: dict[str, Any], now: str) -> str:
    return f"""
You are StudentOS schedule extraction.

The image/document has already been OCR/extracted into text and classified as schedule_data.
Convert it into calendar suggestion events.

Rules:
- Return 0 to 40 events.
- For a weekly timetable, create one event per recurring class/lab slot.
- For weekly timetable slots, set isRepeating true and recurrenceRule to an RFC 5545 weekly RRULE like "RRULE:FREQ=WEEKLY;BYDAY=MO".
- For recurring events, set timeZone to "Asia/Kolkata".
- Resolve day names relative to current date by choosing the next occurrence of that weekday.
- Ignore faculty/people names when creating events.
- Put room/building/lab in location, never in title.
- If a class cell contains a parenthesized room like "(CL-5)", title should omit it and location should be "CL-5".
- Title must be only the class/course label.
- Return compact minified JSON. Do not use markdown fences.

Return only JSON:
{{
  "events": [
    {{
      "title": "Course or event title",
      "startDateTime": "ISO-8601 datetime",
      "endDateTime": "ISO-8601 datetime",
      "isRepeating": true,
      "recurrenceRule": "RRULE:FREQ=WEEKLY;BYDAY=MO",
      "timeZone": "Asia/Kolkata",
      "location": "room or null",
      "source": "timetable"
    }}
  ]
}}

Current time: {now}
Image/document record:
{json.dumps(record, indent=2)}
""".strip()


def vision_extraction_prompt(user_message: str, now: str | None = None) -> str:
    now_line = f"Current time: {now}" if now else "Current time: unknown"
    return f"""
You are StudentOS image ingestion. Extract useful student data from the uploaded image and optional user message.

Do not explain your reasoning. Return final JSON in assistant content only.

Classify the result into exactly one stream:
- schedule_data: timetable, calendar event, deadline, quiz, exam, assignment
- finance_data: receipt, bill, fee, payment, transaction, budget
- wellbeing_data: health, hydration, sleep, medicine, fitness, habit
- other_data: anything else

If stream is schedule_data and the image is a timetable:
- extractedText must include every visible class/lab slot as separate lines.
- Each line should include day, start time, end time, class/course label, and room/location if visible.
- Do not only return the course legend or faculty list.

Return only JSON:
{{
  "stream": "schedule_data|finance_data|wellbeing_data|other_data",
  "subcategory": "short_subcategory",
  "title": "short title",
  "summary": "1-3 sentence useful summary",
  "extractedText": "important extracted text",
  "structuredData": {{
    "dates": [],
    "amounts": [],
    "tasks": [],
    "people": [],
    "locations": [],
    "scheduleSlots": []
  }}
}}

{now_line}
Optional user message: {user_message or "(none)"}
""".strip()
