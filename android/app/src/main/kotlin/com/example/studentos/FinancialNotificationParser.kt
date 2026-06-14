package com.example.studentos

import org.json.JSONObject
import java.util.Locale
import java.util.zip.CRC32

object FinancialNotificationParser {
    private val financeKeywords = listOf(
        "a/c", "acct", "account", "bank", "upi", "imps", "neft", "rtgs", "atm",
        "card", "debit card", "credit card", "wallet", "balance", "txn", "transaction",
        "debited", "debit", "spent", "paid", "sent", "withdrawn", "withdrawal",
        "credited", "credit", "received", "deposited", "transferred", "refund",
        "purchase", "payment", "autopay", "mandate", "emi"
    )

    private val debitKeywords = listOf(
        "debited", "debit", "spent", "paid", "sent", "withdrawn", "withdrawal",
        "purchase", "payment", "dr", "deducted"
    )

    private val creditKeywords = listOf(
        "credited", "credit", "received", "deposited", "refund", "cashback", "cr"
    )

    private val amountPatterns = listOf(
        Regex("(?:rs\\.?|inr|₹)\\s*([0-9][0-9,]*(?:\\.\\d{1,2})?)", RegexOption.IGNORE_CASE),
        Regex("([0-9][0-9,]*(?:\\.\\d{1,2})?)\\s*(?:rs\\.?|inr|₹)", RegexOption.IGNORE_CASE)
    )

    private val phoneLikeSender = Regex("^\\+?\\d[\\d\\s-]{6,}$")
    private val bankSenderLike = Regex("^[A-Z]{2}-?[A-Z0-9-]{3,}$")

    fun parse(payload: JSONObject): JSONObject? {
        val text = searchableText(payload)
        if (text.isBlank()) return null

        val lower = text.lowercase(Locale.US)
        if (financeKeywords.none { lower.contains(it) }) return null

        val amount = extractAmount(text) ?: return null
        val direction = direction(lower) ?: return null

        if (!hasTrustedSenderShape(payload)) {
            return null
        }

        val transaction = JSONObject()
        transaction.put("id", transactionId(payload))
        transaction.put("amount", amount)
        transaction.put("direction", direction)
        transaction.put("currency", "INR")
        transaction.put("sourceApp", payload.optString("appLabel", payload.optString("appPackageName")))
        transaction.put("sourcePackage", payload.optString("appPackageName"))
        transaction.put("sender", payload.optString("rawNotificationTitle"))
        transaction.put("message", payload.optString("rawNotificationText"))
        transaction.put("postTime", payload.optLong("postTime"))
        return transaction
    }

    private fun transactionId(payload: JSONObject): String {
        val key = payload.optString("notificationKey")
        val postTime = payload.optLong("postTime")
        val message = payload.optString("rawNotificationText")
        val checksum = CRC32()
        checksum.update(message.toByteArray(Charsets.UTF_8))
        return "$key|$postTime|${checksum.value}"
    }

    private fun searchableText(payload: JSONObject): String {
        return listOf(
            payload.optString("appLabel"),
            payload.optString("rawNotificationTitle"),
            payload.optString("rawNotificationText"),
            payload.optString("conversationTitle"),
            payload.optString("messageText")
        ).filter { it.isNotBlank() && it != "null" }
            .joinToString(separator = "\n")
    }

    private fun extractAmount(text: String): Double? {
        for (pattern in amountPatterns) {
            val match = pattern.find(text) ?: continue
            return match.groupValues[1].replace(",", "").toDoubleOrNull()
        }
        return null
    }

    private fun direction(lower: String): String? {
        val isDebit = debitKeywords.any { lower.contains(it) }
        val isCredit = creditKeywords.any { lower.contains(it) }
        return when {
            isDebit && !isCredit -> "debit"
            isCredit && !isDebit -> "credit"
            lower.contains("debited") -> "debit"
            lower.contains("credited") -> "credit"
            else -> null
        }
    }

    private fun hasTrustedSenderShape(payload: JSONObject): Boolean {
        val packageName = payload.optString("appPackageName")
        if (packageName.contains("bank", ignoreCase = true) ||
            packageName.contains("pay", ignoreCase = true) ||
            packageName.contains("phonepe", ignoreCase = true) ||
            packageName.contains("gpay", ignoreCase = true)
        ) {
            return true
        }

        val sender = payload.optString("rawNotificationTitle").trim()
        if (sender.isBlank()) return false
        if (phoneLikeSender.matches(sender)) return false

        return bankSenderLike.matches(sender.uppercase(Locale.US)) ||
            sender.any { it.isLetter() } && (sender.any { it.isDigit() } || sender.contains("-"))
    }
}
