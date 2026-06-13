# notification_reading

This feature owns notification ingestion, parsing, and normalization.

## Responsibilities

- Read incoming notification payloads from Android or a connected ingestion layer.
- Normalize raw notification data into a clean app-friendly format.
- Expose data that other features can consume without embedding UI concerns here.

## LLM Extraction Contract

The feature now includes both sides of the extraction boundary:

- a raw notification input payload that captures what the model sees
- a strict output contract for the model response

### Raw Input Payload

The raw payload is defined in `models/notification_llm_input.dart` and should carry:

- app metadata such as package name and label
- notification identity such as key and post time
- the visible title and text
- parsed messaging hints when available, such as sender and conversation title
- the normalized extras map
- any available action metadata

### Prompt Builder

The prompt builder lives in `service/notification_prompt_builder.dart` and produces a JSON-only extraction prompt from the raw payload. It is intentionally strict so the model can be swapped later without changing the contract.

The feature now defines a small JSON contract for the next stage of extraction.

Required output fields:

- `type`: currently `event`
- `startDateTime`: ISO 8601 datetime string
- `endDateTime`: ISO 8601 datetime string
- `isRepeating`: boolean
- `repeat`: optional repeat encoding object when `isRepeating` is true

Recommended repeat encoding:

- `format`: use `rrule` when possible
- `value`: the encoded recurrence rule, preferably RFC 5545 style text

Optional fields:

- `summary`: short human-readable title for the event
- `timeZone`: timezone identifier if the datetime is not fully self-contained

Example:

```json
{
	"type": "event",
	"startDateTime": "2026-06-13T10:00:00+05:30",
	"endDateTime": "2026-06-13T11:00:00+05:30",
	"isRepeating": true,
	"repeat": {
		"format": "rrule",
		"value": "FREQ=WEEKLY;BYDAY=MO,WE,FR"
	},
	"summary": "Team meeting"
}
```

## Boundaries

- No app screens or tabs should live here.
- This feature should stay focused on service logic and data shaping.
