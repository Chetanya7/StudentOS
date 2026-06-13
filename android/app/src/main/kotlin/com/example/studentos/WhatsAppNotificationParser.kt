package com.example.studentos

import android.os.Bundle
import android.service.notification.StatusBarNotification

data class WhatsAppConversation(
    val packageName: String,
    val conversationTitle: String?,
    val senderName: String?,
    val messageText: String?,
    val isGroupConversation: Boolean,
)

object WhatsAppNotificationParser {
    fun parse(sbn: StatusBarNotification): WhatsAppConversation {
        val extras = sbn.notification.extras
        val title = extras.getCharSequence("android.title")?.toString()
        val text = extras.getCharSequence("android.text")?.toString()
        val isGroupConversation = extras.getBoolean("android.isGroupConversation", false)
        val senderName = extractSenderName(extras, title)

        return WhatsAppConversation(
            packageName = sbn.packageName,
            conversationTitle = title,
            senderName = senderName,
            messageText = text,
            isGroupConversation = isGroupConversation,
        )
    }

    fun matchesWhitelist(context: android.content.Context, conversation: WhatsAppConversation): Boolean {
        val people = NotificationFilterStore.getWhatsappPeopleWhitelist(context)
        val groups = NotificationFilterStore.getWhatsappGroupsWhitelist(context)

        if (conversation.isGroupConversation) {
            if (groups.isEmpty()) {
                return true
            }

            return conversation.conversationTitle != null && groups.contains(conversation.conversationTitle)
        }

        if (people.isEmpty()) {
            return true
        }

        val candidates = buildSet {
            conversation.conversationTitle?.let { add(it) }
            conversation.senderName?.let { add(it) }
        }

        return candidates.any { people.contains(it) }
    }

    private fun extractSenderName(extras: Bundle, fallbackTitle: String?): String? {
        val messages = extras.getParcelableArray("android.messages")
        if (!messages.isNullOrEmpty()) {
            messages.forEach { entry ->
                val bundle = entry as? Bundle ?: return@forEach
                val sender = bundle.getCharSequence("sender")?.toString()
                if (!sender.isNullOrBlank()) {
                    return sender
                }

                val senderPerson = bundle.get("sender_person")?.toString()
                if (senderPerson != null) {
                    return senderPerson.toString()
                }
            }
        }

        return fallbackTitle
    }
}
