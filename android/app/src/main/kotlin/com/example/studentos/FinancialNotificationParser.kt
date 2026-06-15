package com.example.studentos

import org.json.JSONObject
import java.util.Locale
import java.util.zip.CRC32

object FinancialNotificationParser {
    private val financeKeywords = listOf(
        "a/c", "ac", "acct", "account", "bank", "upi", "imps", "neft", "rtgs", "atm",
        "card", "debit card", "credit card", "wallet", "balance", "txn", "txnid",
        "transaction", "utr", "rrn", "ref no", "reference no", "cheque", "chq",
        "debited", "debit", "dr", "spent", "paid", "sent", "withdrawn", "withdrawal",
        "credited", "credit", "cr", "received", "deposited", "transferred", "refund",
        "purchase", "payment", "autopay", "mandate", "emi", "pos", "ecom", "netbanking",
        "available balance", "avl bal", "ledger balance", "credited to", "debited from"
    )

    private val debitKeywords = listOf(
        "debited", "debit", "spent", "paid", "sent", "withdrawn", "withdrawal",
        "purchase", "payment", "dr", "deducted", "charged", "used at", "spent on",
        "transferred to", "paid to", "sent to", "debit card", "atm wdl", "cash wdl",
        "pos", "ecom", "upi p2m", "upi p2p", "mandate executed"
    )

    private val creditKeywords = listOf(
        "credited", "credit", "received", "deposited", "refund", "cashback", "cr",
        "transferred from", "received from", "credited to", "salary", "reversal",
        "interest paid", "upi collect", "deposit"
    )

    private val amountPatterns = listOf(
        Regex("(?:rs\\.?|inr|₹)\\s*([0-9][0-9,]*(?:\\.\\d{1,2})?)", RegexOption.IGNORE_CASE),
        Regex("([0-9][0-9,]*(?:\\.\\d{1,2})?)\\s*(?:rs\\.?|inr|₹)", RegexOption.IGNORE_CASE),
        Regex("(?:amount|amt)\\s*(?:of)?\\s*(?:rs\\.?|inr|₹)?\\s*([0-9][0-9,]*(?:\\.\\d{1,2})?)", RegexOption.IGNORE_CASE)
    )

    private val phoneLikeSender = Regex("^\\+?\\d[\\d\\s-]{6,}$")
    private val bankSenderLike = Regex("^(?:[A-Z]{2}-?)?[A-Z0-9][A-Z0-9-]{2,}$")
    private val knownBankOrPaymentSenderHints = listOf(
        "sbi", "hdfc", "icici", "axis", "kotak", "pnb", "bob", "boi", "canbnk",
        "union", "indus", "yesbnk", "idfc", "idbi", "federal", "rbl", "dbs",
        "hsbc", "citi", "scb", "au", "equitas", "paytm", "phonepe", "gpay",
        "amazonpay", "mobikwik", "freecharge", "cred", "slice", "fi", "jupiter",
        "navi", "bhim", "npci", "upi"
    )

    fun parse(payload: JSONObject): JSONObject? {
        val text = searchableText(payload)
        if (text.isBlank()) return null

        val lower = text.lowercase(Locale.US)
        if (!hasFinancialShape(lower)) return null

        val amount = extractAmount(text) ?: return null
        val direction = direction(lower) ?: return null

        val trustedSender = hasTrustedSenderShape(payload)

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
        // HACKATHON DEMO SHIM: accept bank-shaped messages even from untrusted
        // personal senders so judges can demo transaction ingestion with any
        // phone. Replace this with strict sender verification before production.
        transaction.put("trustedSender", trustedSender)
        return transaction
    }

    fun looksLikeFinancialNotification(payload: JSONObject): Boolean {
        val text = searchableText(payload)
        if (text.isBlank()) return false

        val lower = text.lowercase(Locale.US)
        return hasFinancialShape(lower) && extractAmount(text) != null
    }

    fun describeDecision(payload: JSONObject): String {
        val text = searchableText(payload)
        if (text.isBlank()) return "not financial: blank searchable text"

        val lower = text.lowercase(Locale.US)
        val hasShape = hasFinancialShape(lower)
        val amount = extractAmount(text)
        val direction = direction(lower)
        val trustedSender = hasTrustedSenderShape(payload)

        return "financialDecision(shape=$hasShape, amount=$amount, direction=$direction, trustedSender=$trustedSender, sender=\"${payload.optString("rawNotificationTitle")}\", text=\"${payload.optString("rawNotificationText")}\")"
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

    private fun hasFinancialShape(lower: String): Boolean {
        val hasKeyword = financeKeywords.any { lower.contains(it) }
        val hasAccountLikeText =
            Regex("\\b(?:xx|x{2,}|\\*{2,})\\d{2,}\\b", RegexOption.IGNORE_CASE).containsMatchIn(lower) ||
                Regex("\\b(?:a/c|acct|account)\\b", RegexOption.IGNORE_CASE).containsMatchIn(lower)
        val hasNetworkRef =
            lower.contains("upi") ||
                lower.contains("utr") ||
                lower.contains("rrn") ||
                lower.contains("imps") ||
                lower.contains("neft") ||
                lower.contains("rtgs")

        return hasKeyword && (hasAccountLikeText || hasNetworkRef || lower.contains("bank") || lower.contains("card"))
    }

    private fun direction(lower: String): String? {
        val isDebit = debitKeywords.any { lower.containsWordLike(it) }
        val isCredit = creditKeywords.any { lower.containsWordLike(it) }
        return when {
            lower.contains("debited") || lower.contains("debited from") -> "debit"
            lower.contains("credited") || lower.contains("credited to") -> "credit"
            lower.contains("withdrawn") || lower.contains("withdrawal") -> "debit"
            lower.contains("received") || lower.contains("received from") -> "credit"
            isDebit && !isCredit -> "debit"
            isCredit && !isDebit -> "credit"
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

        val normalizedSender = sender.lowercase(Locale.US).replace(Regex("[^a-z0-9]"), "")
        if (knownBankOrPaymentSenderHints.any { normalizedSender.contains(it) }) {
            return true
        }

        return bankSenderLike.matches(sender.uppercase(Locale.US)) ||
            sender.any { it.isLetter() } && (sender.any { it.isDigit() } || sender.contains("-"))
    }

    private fun String.containsWordLike(value: String): Boolean {
        val escaped = Regex.escape(value)
        return Regex("(^|[^a-z0-9])$escaped([^a-z0-9]|\$)", RegexOption.IGNORE_CASE).containsMatchIn(this)
    }
}
