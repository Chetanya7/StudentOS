package com.example.studentos

import android.app.Notification
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
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
