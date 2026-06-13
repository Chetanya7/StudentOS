package com.example.studentos

import android.content.Context
import android.service.notification.StatusBarNotification

object NotificationFilterStore {
    private const val PREFS = "studentos_notification_filters"
    private const val KEY_ENABLED_APPS = "enabled_apps"
    private const val KEY_WHATSAPP_PEOPLE = "whatsapp_people_whitelist"
    private const val KEY_WHATSAPP_GROUPS = "whatsapp_groups_whitelist"

    const val WHATSAPP_PACKAGE = "com.whatsapp"
    const val GMAIL_PACKAGE = "com.google.android.gm"
    const val TELEGRAM_PACKAGE = "org.telegram.messenger"
    const val OUTLOOK_PACKAGE = "com.microsoft.office.outlook"
    const val TEAMS_PACKAGE = "com.microsoft.teams"

    private val defaultEnabledApps = linkedSetOf(
        WHATSAPP_PACKAGE,
        GMAIL_PACKAGE,
        TELEGRAM_PACKAGE,
        OUTLOOK_PACKAGE,
        TEAMS_PACKAGE,
    )

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun getEnabledApps(context: Context): Set<String> {
        val sharedPreferences = prefs(context)
        val current = sharedPreferences.getStringSet(KEY_ENABLED_APPS, null)
        if (current != null) {
            return current.toSet()
        }

        val seeded = defaultEnabledApps.toSet()
        sharedPreferences.edit().putStringSet(KEY_ENABLED_APPS, seeded).apply()
        return seeded
    }

    fun setEnabledApps(context: Context, apps: Set<String>) {
        prefs(context).edit().putStringSet(KEY_ENABLED_APPS, apps.toSet()).apply()
    }

    fun addEnabledApp(context: Context, packageName: String) {
        val apps = getEnabledApps(context).toMutableSet()
        apps.add(packageName)
        setEnabledApps(context, apps)
    }

    fun removeEnabledApp(context: Context, packageName: String) {
        val apps = getEnabledApps(context).toMutableSet()
        apps.remove(packageName)
        setEnabledApps(context, apps)
    }

    fun isEnabledApp(context: Context, packageName: String): Boolean {
        return getEnabledApps(context).contains(packageName)
    }

    fun getWhatsappPeopleWhitelist(context: Context): Set<String> {
        return prefs(context).getStringSet(KEY_WHATSAPP_PEOPLE, emptySet())?.toSet().orEmpty()
    }

    fun getWhatsappGroupsWhitelist(context: Context): Set<String> {
        return prefs(context).getStringSet(KEY_WHATSAPP_GROUPS, emptySet())?.toSet().orEmpty()
    }

    fun setWhatsappPeopleWhitelist(context: Context, values: Set<String>) {
        prefs(context).edit().putStringSet(KEY_WHATSAPP_PEOPLE, values.toSet()).apply()
    }

    fun setWhatsappGroupsWhitelist(context: Context, values: Set<String>) {
        prefs(context).edit().putStringSet(KEY_WHATSAPP_GROUPS, values.toSet()).apply()
    }

    fun addWhatsappPerson(context: Context, name: String) {
        val values = getWhatsappPeopleWhitelist(context).toMutableSet()
        values.add(name)
        setWhatsappPeopleWhitelist(context, values)
    }

    fun removeWhatsappPerson(context: Context, name: String) {
        val values = getWhatsappPeopleWhitelist(context).toMutableSet()
        values.remove(name)
        setWhatsappPeopleWhitelist(context, values)
    }

    fun addWhatsappGroup(context: Context, name: String) {
        val values = getWhatsappGroupsWhitelist(context).toMutableSet()
        values.add(name)
        setWhatsappGroupsWhitelist(context, values)
    }

    fun removeWhatsappGroup(context: Context, name: String) {
        val values = getWhatsappGroupsWhitelist(context).toMutableSet()
        values.remove(name)
        setWhatsappGroupsWhitelist(context, values)
    }

    fun shouldProcessNotification(context: Context, sbn: StatusBarNotification): Boolean {
        if (!isEnabledApp(context, sbn.packageName)) {
            return false
        }

        if (sbn.packageName != WHATSAPP_PACKAGE) {
            return true
        }

        val conversation = WhatsAppNotificationParser.parse(sbn)
        return WhatsAppNotificationParser.matchesWhitelist(context, conversation)
    }

    fun describeFilterDecision(context: Context, sbn: StatusBarNotification): String {
        if (!isEnabledApp(context, sbn.packageName)) {
            return "ignored: app not enabled"
        }

        if (sbn.packageName != WHATSAPP_PACKAGE) {
            return "allowed: generic app"
        }

        val conversation = WhatsAppNotificationParser.parse(sbn)
        return if (WhatsAppNotificationParser.matchesWhitelist(context, conversation)) {
            "allowed: whatsapp conversation matched"
        } else {
            "ignored: whatsapp conversation not whitelisted"
        }
    }
}
