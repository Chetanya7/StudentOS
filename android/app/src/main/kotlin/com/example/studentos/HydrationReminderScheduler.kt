package com.example.studentos

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

object HydrationReminderScheduler {
	const val ACTION_SHOW = "com.example.studentos.HYDRATION_SHOW"
	const val ACTION_DRANK = "com.example.studentos.HYDRATION_DRANK"
	const val ACTION_SNOOZE = "com.example.studentos.HYDRATION_SNOOZE"
	const val CHANNEL_ID = "hydration_reminders"

	private const val FLUTTER_PREFS = "FlutterSharedPreferences"
	private const val SETTINGS_KEY = "flutter.hydration_settings_json"
	private const val ENTRIES_KEY = "flutter.hydration_entries_json"
	private const val REMINDER_REQUEST_CODE = 44001
	private const val NOTIFICATION_ID = 44002

	fun saveSettingsAndSchedule(context: Context, settings: Map<String, Any?>) {
		val json = JSONObject(settings).toString()
		context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
			.edit()
			.putString(SETTINGS_KEY, json)
			.apply()
		scheduleNext(context)
	}

	fun cancel(context: Context) {
		val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
		alarmManager.cancel(reminderPendingIntent(context))
		val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
		manager.cancel(NOTIFICATION_ID)
	}

	fun scheduleNext(context: Context) {
		try {
			val settings = readSettings(context)
			if (!settings.optBoolean("enabled", false)) {
				cancel(context)
				return
			}

			val triggerAt = nextReminderTime(settings, readTodayAmount(context))
			scheduleAt(context, triggerAt.timeInMillis)
		} catch (e: Exception) {
			Log.e("HydrationReminder", "Unable to schedule hydration reminder", e)
		}
	}

	fun snooze(context: Context) {
		cancelNotification(context)
		val triggerAt = Calendar.getInstance().apply {
			add(Calendar.MINUTE, 15)
		}
		scheduleAt(context, triggerAt.timeInMillis)
	}

	fun markDrank(context: Context) {
		val settings = readSettings(context)
		val goalMl = settings.optInt("dailyGoalMl", 2000)
		val entries = readEntries(context)
		val today = dateKey(Date())
		var updated = false

		for (index in 0 until entries.length()) {
			val entry = entries.optJSONObject(index) ?: continue
			if (entry.optString("date") == today) {
				entry.put("amountMl", entry.optInt("amountMl", 0) + 250)
				entry.put("goalMl", goalMl)
				updated = true
				break
			}
		}

		if (!updated) {
			entries.put(
				JSONObject()
					.put("date", today)
					.put("amountMl", 250)
					.put("goalMl", goalMl)
			)
		}

		context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
			.edit()
			.putString(ENTRIES_KEY, entries.toString())
			.apply()

		cancelNotification(context)
		showPositiveReinforcement(context, readTodayAmount(context), goalMl)
		scheduleNext(context)
	}

	fun showReminder(context: Context) {
		val settings = readSettings(context)
		if (!settings.optBoolean("enabled", false)) return

		val goalMl = settings.optInt("dailyGoalMl", 2000)
		if (readTodayAmount(context) >= goalMl) {
			scheduleNext(context)
			return
		}

		createChannel(context)

		val openIntent = Intent(context, MainActivity::class.java).apply {
			flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
		}
		val openPendingIntent = PendingIntent.getActivity(
			context,
			0,
			openIntent,
			PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
		)
		val drankIntent = Intent(context, HydrationReminderReceiver::class.java).apply {
			action = ACTION_DRANK
		}
		val snoozeIntent = Intent(context, HydrationReminderReceiver::class.java).apply {
			action = ACTION_SNOOZE
		}

		val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			Notification.Builder(context, CHANNEL_ID)
		} else {
			@Suppress("DEPRECATION")
			Notification.Builder(context)
		}

		if (!settings.optBoolean("soundEnabled", true)) {
			@Suppress("DEPRECATION")
			builder
				.setDefaults(0)
				.setSound(null)
				.setVibrate(null)
		}

		val notification = builder
			.setSmallIcon(android.R.drawable.ic_dialog_info)
			.setContentTitle("Hydration Check 💧")
			.setContentText("Take a moment to drink some water.")
			.setStyle(Notification.BigTextStyle().bigText("Take a moment to drink some water."))
			.setContentIntent(openPendingIntent)
			.setAutoCancel(true)
			.addAction(
				android.R.drawable.ic_menu_add,
				"Drank 250 ml",
				PendingIntent.getBroadcast(
					context,
					1,
					drankIntent,
					PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
				)
			)
			.addAction(
				android.R.drawable.ic_menu_recent_history,
				"Snooze 15 min",
				PendingIntent.getBroadcast(
					context,
					2,
					snoozeIntent,
					PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
				)
			)
			.build()

		val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
		manager.notify(NOTIFICATION_ID, notification)
		scheduleNext(context)
	}

	private fun scheduleAt(context: Context, triggerAtMillis: Long) {
		val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
		val pendingIntent = reminderPendingIntent(context)
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
			alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
		} else {
			alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
		}
	}

	private fun nextReminderTime(settings: JSONObject, todayAmountMl: Int): Calendar {
		val now = Calendar.getInstance()
		val goalMl = settings.optInt("dailyGoalMl", 2000)
		val startMinutes = settings.optInt("startMinutes", 8 * 60)
		val endMinutes = settings.optInt("endMinutes", 22 * 60)
		val frequencyMinutes = settings.optInt("frequencyMinutes", 90).coerceAtLeast(15)
		val start = atMinutes(now, startMinutes)
		val end = atMinutes(now, endMinutes)

		if (todayAmountMl >= goalMl || now.after(end)) {
			return atMinutes(now, startMinutes).apply {
				add(Calendar.DAY_OF_YEAR, 1)
			}
		}

		if (now.before(start)) return start

		return Calendar.getInstance().apply {
			add(Calendar.MINUTE, frequencyMinutes)
			if (after(end)) {
				timeInMillis = atMinutes(now, startMinutes).apply {
					add(Calendar.DAY_OF_YEAR, 1)
				}.timeInMillis
			}
		}
	}

	private fun atMinutes(source: Calendar, minutes: Int): Calendar {
		return (source.clone() as Calendar).apply {
			set(Calendar.HOUR_OF_DAY, minutes / 60)
			set(Calendar.MINUTE, minutes % 60)
			set(Calendar.SECOND, 0)
			set(Calendar.MILLISECOND, 0)
		}
	}

	private fun reminderPendingIntent(context: Context): PendingIntent {
		val intent = Intent(context, HydrationReminderReceiver::class.java).apply {
			action = ACTION_SHOW
		}
		return PendingIntent.getBroadcast(
			context,
			REMINDER_REQUEST_CODE,
			intent,
			PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
		)
	}

	private fun readSettings(context: Context): JSONObject {
		val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
		val source = prefs.getString(SETTINGS_KEY, null)
		return if (source.isNullOrBlank()) JSONObject() else JSONObject(source)
	}

	private fun readEntries(context: Context): JSONArray {
		val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
		val source = prefs.getString(ENTRIES_KEY, null)
		return if (source.isNullOrBlank()) JSONArray() else JSONArray(source)
	}

	private fun readTodayAmount(context: Context): Int {
		val today = dateKey(Date())
		val entries = readEntries(context)
		for (index in 0 until entries.length()) {
			val entry = entries.optJSONObject(index) ?: continue
			if (entry.optString("date") == today) return entry.optInt("amountMl", 0)
		}
		return 0
	}

	private fun showPositiveReinforcement(context: Context, amountMl: Int, goalMl: Int) {
		createChannel(context)
		val message = if (amountMl >= goalMl) {
			"Daily hydration goal reached. Nice work."
		} else {
			"Logged 250 ml. ${goalMl - amountMl} ml remaining today."
		}
		val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			Notification.Builder(context, CHANNEL_ID)
		} else {
			@Suppress("DEPRECATION")
			Notification.Builder(context)
		}
		val notification = builder
			.setSmallIcon(android.R.drawable.ic_dialog_info)
			.setContentTitle("Water logged")
			.setContentText(message)
			.setAutoCancel(true)
			.build()
		val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
		manager.notify(NOTIFICATION_ID + 1, notification)
	}

	private fun cancelNotification(context: Context) {
		val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
		manager.cancel(NOTIFICATION_ID)
	}

	private fun createChannel(context: Context) {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
		val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
		val channel = NotificationChannel(
			CHANNEL_ID,
			"Hydration reminders",
			NotificationManager.IMPORTANCE_DEFAULT
		).apply {
			description = "Configurable water intake reminders"
		}
		manager.createNotificationChannel(channel)
	}

	private fun dateKey(date: Date): String {
		return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(date)
	}
}
