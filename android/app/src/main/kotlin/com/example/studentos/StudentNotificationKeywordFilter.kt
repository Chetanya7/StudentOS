package com.example.studentos

import org.json.JSONObject

object StudentNotificationKeywordFilter {
    private val keywordPatterns = listOf(
        // Assessments and evaluation.
        "quiz", "test", "exam", "midterm", "endsem", "end sem", "final", "viva", "oral",
        "practical", "lab exam", "assessment", "evaluation", "internal", "external",
        "marks", "grade", "result", "revaluation", "makeup", "make-up",

        // Assignments and coursework.
        "assignment", "homework", "hw", "worksheet", "problem set", "pset", "submission",
        "submit", "deadline", "due", "turn in", "upload", "moodle", "classroom",
        "canvas", "blackboard", "lms", "portal", "form", "google form",

        // Classes, labs, and academic sessions.
        "lecture", "class", "tutorial", "tut", "lab", "workshop", "seminar", "webinar",
        "recitation", "extra class", "doubt session", "remedial", "makeup class",
        "guest lecture", "orientation", "induction",

        // Schedule and calendar language.
        "today", "tomorrow", "tonight", "next week", "next monday", "next tuesday",
        "next wednesday", "next thursday", "next friday", "next saturday", "next sunday",
        "schedule", "scheduled", "rescheduled", "postponed", "preponed", "cancelled",
        "canceled", "timing", "time table", "timetable", "slot", "venue", "room",
        "auditorium", "hall", "meet at", "starts at", "from", "to",

        // Projects and presentations.
        "project", "milestone", "demo", "presentation", "ppt", "slides", "report",
        "proposal", "review", "code review", "poster", "abstract", "prototype",

        // Registration, admin, and campus operations.
        "registration", "enrollment", "enrolment", "course add", "course drop",
        "add/drop", "fee", "fees", "payment", "scholarship", "hostel", "mess",
        "library", "id card", "admit card", "hall ticket", "certificate", "transcript",
        "attendance", "biometric", "leave", "holiday", "notice", "circular",

        // Clubs, events, and campus life.
        "club", "committee", "society", "fest", "hackathon", "competition", "contest",
        "tryout", "audition", "meeting", "meetup", "practice", "rehearsal", "sports",
        "match", "tournament", "volunteer", "recruitment", "interview",

        // Career and applications.
        "internship", "placement", "job", "resume", "cv", "interview", "oa",
        "online assessment", "application", "apply", "shortlist", "pre-placement",
        "ppo", "career", "company", "drive",
    ).map { Regex("\\b${Regex.escape(it)}\\b", RegexOption.IGNORE_CASE) }

    private val timePatterns = listOf(
        Regex("\\b\\d{1,2}[:.]\\d{2}\\b"),
        Regex("\\b\\d{1,2}\\s*(am|pm)\\b", RegexOption.IGNORE_CASE),
        Regex("\\b\\d{1,2}\\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)\\b", RegexOption.IGNORE_CASE),
        Regex("\\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)\\s*\\d{1,2}\\b", RegexOption.IGNORE_CASE),
        Regex("\\b\\d{1,2}/\\d{1,2}(/\\d{2,4})?\\b"),
        Regex("\\b\\d{1,2}-\\d{1,2}(-\\d{2,4})?\\b"),
    )

    fun shouldQueueForAi(payload: JSONObject): Boolean {
        val text = searchableText(payload)
        if (text.isBlank()) return false

        return keywordPatterns.any { it.containsMatchIn(text) } ||
            timePatterns.any { it.containsMatchIn(text) }
    }

    fun describe(payload: JSONObject): String {
        val text = searchableText(payload)
        val keyword = keywordPatterns.firstOrNull { it.containsMatchIn(text) }
        if (keyword != null) return "matched keyword pattern ${keyword.pattern}"

        val timePattern = timePatterns.firstOrNull { it.containsMatchIn(text) }
        if (timePattern != null) return "matched time/date pattern ${timePattern.pattern}"

        return "no student-life keywords"
    }

    private fun searchableText(payload: JSONObject): String {
        return listOf(
            payload.optString("rawNotificationTitle"),
            payload.optString("rawNotificationText"),
            payload.optString("conversationTitle"),
            payload.optString("messageText"),
            payload.optString("senderName"),
            payload.optString("appLabel"),
        ).filter { it.isNotBlank() && it != "null" }
            .joinToString(separator = "\n")
    }
}
