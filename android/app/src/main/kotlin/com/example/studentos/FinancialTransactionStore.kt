package com.example.studentos

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object FinancialTransactionStore {
    private const val PREFS = "studentos_financial_transactions"
    private const val KEY_TRANSACTIONS = "transactions"
    private const val MAX_TRANSACTIONS = 200

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun add(context: Context, transaction: JSONObject) {
        val transactions = JSONArray(prefs(context).getString(KEY_TRANSACTIONS, "[]"))
        val id = transaction.optString("id")

        for (index in 0 until transactions.length()) {
            val existing = transactions.optJSONObject(index)
            if (existing?.optString("id") == id) {
                return
            }
        }

        transactions.put(transaction)

        val trimmed = JSONArray()
        val start = maxOf(0, transactions.length() - MAX_TRANSACTIONS)
        for (index in start until transactions.length()) {
            trimmed.put(transactions.get(index))
        }

        prefs(context).edit().putString(KEY_TRANSACTIONS, trimmed.toString()).apply()
    }

    fun list(context: Context): String {
        return prefs(context).getString(KEY_TRANSACTIONS, "[]") ?: "[]"
    }
}
