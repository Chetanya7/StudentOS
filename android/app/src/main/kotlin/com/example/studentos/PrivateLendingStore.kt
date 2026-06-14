package com.example.studentos

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object PrivateLendingStore {
    private const val PREFS = "studentos_private_lending"
    private const val KEY_ENTRIES = "entries"
    private const val KEY_BUDGET = "budget"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun list(context: Context): String {
        return prefs(context).getString(KEY_ENTRIES, "[]") ?: "[]"
    }

    fun add(context: Context, entry: JSONObject) {
        val entries = JSONArray(list(context))
        entries.put(entry)
        prefs(context).edit().putString(KEY_ENTRIES, entries.toString()).apply()
    }

    fun getBudget(context: Context): String {
        return prefs(context).getString(KEY_BUDGET, "{\"budgetAmount\":0,\"alertAtAmount\":0,\"balanceBaseAmount\":0}") ?: "{\"budgetAmount\":0,\"alertAtAmount\":0,\"balanceBaseAmount\":0}"
    }

    fun setBudget(context: Context, budget: JSONObject) {
        prefs(context).edit().putString(KEY_BUDGET, budget.toString()).apply()
    }
}
