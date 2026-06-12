# calendar

This feature owns the calendar tab and everything needed to present schedule information.

## Responsibilities

- Render the calendar tab UI.
- Show events, deadlines, and time-based student schedule data.
- Keep calendar state and presentation logic isolated from other features.

## Boundaries

- Calendar-specific widgets and models can live here.
- Notification ingestion should not be implemented here.
- Assignment-specific workflows should not be implemented here.
