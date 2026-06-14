package com.example.studentos

import android.app.Notification
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.time.OffsetDateTime
import java.util.TreeSet

class NotificationReaderService : NotificationListenerService() {
    private val TAG = "NotificationReader"

    override fun onListenerConnected() {
        Log.i(TAG, "NotificationListenerService connected")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            if (!NotificationFilterStore.shouldProcessNotification(this, sbn)) {
                Log.i(TAG, "Filtered out ${sbn.packageName}: ${NotificationFilterStore.describeFilterDecision(this, sbn)}")
                return
            }

            val payload = buildLlmPayload(sbn)
            val financialTransaction = FinancialNotificationParser.parse(payload)
            if (financialTransaction != null) {
                FinancialTransactionStore.add(this, financialTransaction)
                Log.i(TAG, "Stored financial transaction: $financialTransaction")
                return
            }

            if (!StudentNotificationKeywordFilter.shouldQueueForAi(payload)) {
                Log.i(TAG, "Skipped AI extraction for ${sbn.packageName}: ${StudentNotificationKeywordFilter.describe(payload)}")
                return
            }

            PendingNotificationStore.add(this, payload)
            Log.i(TAG, "Queued notification payload for AI extraction: ${payload.optString("notificationKey")} (${StudentNotificationKeywordFilter.describe(payload)})")
            Log.i(TAG, dumpStatusBarNotification(sbn))
        } catch (e: Exception) {
            Log.e(TAG, "Error reading notification", e)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        try {
            val pkg = sbn.packageName
            Log.i(TAG, "Removed from: $pkg")
        } catch (e: Exception) {
            Log.e(TAG, "Error in onNotificationRemoved", e)
        }
    }

    private fun buildLlmPayload(sbn: StatusBarNotification): JSONObject {
        val notification = sbn.notification
        val extras = notification.extras
        val whatsappConversation = if (sbn.packageName == NotificationFilterStore.WHATSAPP_PACKAGE) {
            WhatsAppNotificationParser.parse(sbn)
        } else {
            null
        }

        val payload = JSONObject()
        payload.put("appPackageName", sbn.packageName)
        payload.put("appLabel", appLabelForPackage(sbn.packageName))
        payload.put("notificationKey", sbn.key)
        payload.put("postTime", sbn.postTime)
        payload.put("channelId", notification.channelId)
        payload.put("category", notification.category)
        payload.put("rawNotificationTitle", extras.getCharSequence("android.title")?.toString())
        payload.put("rawNotificationText", extras.getCharSequence("android.text")?.toString())
        payload.put("summary", extras.getCharSequence("android.title")?.toString())
        payload.put("timeZone", java.util.TimeZone.getDefault().id)
        val currentDateTime = OffsetDateTime.now()
        payload.put("currentDateTime", currentDateTime.toString())
        payload.put("currentDate", currentDateTime.toLocalDate().toString())
        payload.put("extras", bundleToJson(extras))
        payload.put("actions", actionsToJson(notification))

        if (whatsappConversation != null) {
            payload.put("isGroupConversation", whatsappConversation.isGroupConversation)
            payload.put("senderName", whatsappConversation.senderName)
            payload.put("messageText", whatsappConversation.messageText)
            payload.put("conversationTitle", whatsappConversation.conversationTitle)
        }

        return payload
    }

    private fun appLabelForPackage(packageName: String): String? {
        return try {
            val applicationInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(applicationInfo).toString()
        } catch (e: Exception) {
            null
        }
    }

    private fun actionsToJson(notification: Notification): JSONArray {
        val array = JSONArray()
        notification.actions?.forEach { action ->
            val item = JSONObject()
            item.put("title", action.title?.toString())
            item.put("hasRemoteInputs", !action.remoteInputs.isNullOrEmpty())
            item.put("intentDescription", action.actionIntent?.toString())
            array.put(item)
        }
        return array
    }

    private fun bundleToJson(bundle: Bundle): JSONObject {
        val json = JSONObject()
        for (key in bundle.keySet()) {
            json.put(key, jsonValue(bundle.get(key)))
        }
        return json
    }

    private fun jsonValue(value: Any?): Any? {
        return when (value) {
            null -> JSONObject.NULL
            is CharSequence -> value.toString()
            is Number -> value
            is Boolean -> value
            is Bundle -> bundleToJson(value)
            is Array<*> -> JSONArray(value.map { jsonValue(it) })
            is IntArray -> JSONArray(value.toList())
            is LongArray -> JSONArray(value.toList())
            is BooleanArray -> JSONArray(value.toList())
            is FloatArray -> JSONArray(value.toList())
            is DoubleArray -> JSONArray(value.toList())
            else -> value.toString()
        }
    }

    private fun dumpStatusBarNotification(sbn: StatusBarNotification): String {
        val notification = sbn.notification
        val extras = notification.extras
        val whatsappConversation = if (sbn.packageName == NotificationFilterStore.WHATSAPP_PACKAGE) {
            WhatsAppNotificationParser.parse(sbn)
        } else {
            null
        }
        val builder = StringBuilder()

        builder.appendLine("Notification posted")
        builder.appendLine("StatusBarNotification:")
        builder.appendLine("  packageName=${sbn.packageName}")
        builder.appendLine("  key=${sbn.key}")
        builder.appendLine("  id=${sbn.id}")
        builder.appendLine("  tag=${sbn.tag}")
        builder.appendLine("  postTime=${sbn.postTime}")
        builder.appendLine("  isOngoing=${sbn.isOngoing}")
        builder.appendLine("  isClearable=${sbn.isClearable}")
        builder.appendLine("  notification=${notification}")
        builder.appendLine("Notification fields:")
        builder.appendLine("  channelId=${notification.channelId}")
        builder.appendLine("  category=${notification.category}")
        builder.appendLine("  priority=${notification.priority}")
        builder.appendLine("  when=${notification.`when`}")
        builder.appendLine("  flags=${notification.flags}")
        builder.appendLine("  number=${notification.number}")
        builder.appendLine("  visibility=${notification.visibility}")
        builder.appendLine("  tickerText=${notification.tickerText}")
        builder.appendLine("  sortKey=${notification.sortKey}")
        builder.appendLine("  color=${notification.color}")
        builder.appendLine("  defaults=${notification.defaults}")

        if (whatsappConversation != null) {
            builder.appendLine("WhatsApp parsed fields:")
            builder.appendLine("  conversationTitle=${whatsappConversation.conversationTitle}")
            builder.appendLine("  senderName=${whatsappConversation.senderName}")
            builder.appendLine("  messageText=${whatsappConversation.messageText}")
            builder.appendLine("  isGroupConversation=${whatsappConversation.isGroupConversation}")
        }

        val actions = notification.actions
        if (actions.isNullOrEmpty()) {
            builder.appendLine("Actions: none")
        } else {
            builder.appendLine("Actions:")
            actions.forEachIndexed { index, action ->
                val remoteInputs = action.remoteInputs
                    ?.map { it.toString() }
                    ?.joinToString(prefix = "[", postfix = "]")
                    ?: "none"
                builder.appendLine("  [$index] title=${action.title}")
                builder.appendLine("       icon=${action.icon}")
                builder.appendLine("       intent=${action.actionIntent}")
                builder.appendLine("       remoteInputs=$remoteInputs")
            }
        }

        builder.appendLine("Extras:")
        builder.appendLine(dumpBundle(extras))

        return builder.toString()
    }

    private fun dumpBundle(bundle: Bundle): String {
        if (bundle.isEmpty) {
            return "  <empty>"
        }

        val keys = TreeSet(bundle.keySet())
        val builder = StringBuilder()
        for (key in keys) {
            val value = bundle.get(key)
            builder.appendLine("  $key=${formatBundleValue(value)}")
        }
        return builder.toString()
    }

    private fun formatBundleValue(value: Any?): String {
        return when (value) {
            null -> "null"
            is CharSequence -> '"' + value.toString() + '"'
            is Bundle -> "Bundle(${value.keySet().joinToString()})"
            is Array<*> -> value.joinToString(prefix = "[", postfix = "]") { formatBundleValue(it) }
            is IntArray -> value.joinToString(prefix = "[", postfix = "]")
            is LongArray -> value.joinToString(prefix = "[", postfix = "]")
            is BooleanArray -> value.joinToString(prefix = "[", postfix = "]")
            is CharArray -> value.joinToString(prefix = "[", postfix = "]")
            is FloatArray -> value.joinToString(prefix = "[", postfix = "]")
            is DoubleArray -> value.joinToString(prefix = "[", postfix = "]")
            is ShortArray -> value.joinToString(prefix = "[", postfix = "]")
            is ByteArray -> value.joinToString(prefix = "[", postfix = "]")
            else -> value.toString()
        }
    }
}
