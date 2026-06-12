# studentos

Studentos is a student lifecycle AI app built to make college life easier by organizing communication, finances, stress, and scheduling into one system.

## Vision

The goal of Studentos is to become a personal academic and campus assistant that can understand a student’s day-to-day activity, surface useful insights, and help them stay on top of everything that matters during college.

## Core Ideas

- Read and classify notifications from WhatsApp and Android to capture important student updates.
- Pull structured signals from Gmail, Outlook, Telegram, and Microsoft Teams through APIs.
- Build a central database from those sources so the app can track events, reminders, tasks, and communication history.
- Track finances through notifications and related signals to help students understand spending patterns.
- Monitor stress and schedule patterns so the app can highlight overload, conflicts, and risky weeks.
- Provide a chatbot that answers FAQs about all stored student data and insights.

## AI And Infrastructure

The AI services for Studentos are planned to run on an Amazon EC2 instance using vLLM. This backend will support future model serving, inference, and data-driven assistant features.

## Long-Term Direction

Studentos is designed to evolve beyond personal productivity. The stored data and derived signals can later be used by the Amazon marketplace to tailor search and recommendations based on real student needs, habits, and context.

## Current Scope

This repository currently contains the Flutter frontend for the Studentos experience.

## Basic Project Structure

The app should stay split by feature so each part can be owned and developed independently.

```text
lib/
	main.dart
	app/
		app.dart
		router.dart
		theme.dart
	features/
		notification_reading/
			README.md
			service/
			models/
			integration/
		calendar/
			README.md
			calendar_tab.dart
			calendar_model.dart
			widgets/
		assignments/
			README.md
			assignments_tab.dart
			assignment_model.dart
			widgets/
	shared/
		widgets/
		utils/
		services/
```

### Feature Isolation

- `notification_reading/README.md` documents the notification ingestion and parsing boundary. It should not own app UI.
- `calendar/README.md` documents the calendar tab, calendar state, and any event rendering logic.
- `assignments/README.md` documents the assignments tab, assignment state, and task tracking logic.
- `shared/` should only contain reusable UI and utility code that does not belong to a single feature.

## Code Style

See [codestyle.md](codestyle.md) for the project-wide writing and commenting rules.

### Ownership Notes

- Notification reading is intentionally isolated so another person or team can plug in the backend or device-level ingestion later without touching the calendar or assignments flows.
- Each feature should keep its own README so its behavior, responsibilities, and boundaries stay explicit.
- Calendar and assignments are separated so each tab can move independently without tightly coupling their data models or UI logic.
