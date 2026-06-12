# notification_reading

This feature owns notification ingestion, parsing, and normalization.

## Responsibilities

- Read incoming notification payloads from Android or a connected ingestion layer.
- Normalize raw notification data into a clean app-friendly format.
- Expose data that other features can consume without embedding UI concerns here.

## Boundaries

- No app screens or tabs should live here.
- This feature should stay focused on service logic and data shaping.
