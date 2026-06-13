package com.example.studentos

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object PendingNotificationStore {
    private const val PREFS = "studentos_pending_notifications"
    private const val KEY_PAYLOADS = "payloads"
    private const val MAX_PAYLOADS = 50

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun add(context: Context, payload: JSONObject) {
        val payloads = JSONArray(prefs(context).getString(KEY_PAYLOADS, "[]"))
        payloads.put(payload)

        val trimmed = JSONArray()
        val start = maxOf(0, payloads.length() - MAX_PAYLOADS)
        for (index in start until payloads.length()) {
            trimmed.put(payloads.get(index))
        }

        prefs(context).edit().putString(KEY_PAYLOADS, trimmed.toString()).apply()
    }

    fun drain(context: Context): String {
        val payloads = prefs(context).getString(KEY_PAYLOADS, "[]") ?: "[]"
        prefs(context).edit().putString(KEY_PAYLOADS, "[]").apply()
        return payloads
    }
}
