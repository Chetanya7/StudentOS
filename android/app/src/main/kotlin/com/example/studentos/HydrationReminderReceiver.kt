package com.example.studentos

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class HydrationReminderReceiver : BroadcastReceiver() {
	override fun onReceive(context: Context, intent: Intent) {
		when (intent.action) {
			HydrationReminderScheduler.ACTION_SHOW -> {
				HydrationReminderScheduler.showReminder(context)
			}
			HydrationReminderScheduler.ACTION_DRANK -> {
				HydrationReminderScheduler.markDrank(context)
			}
			HydrationReminderScheduler.ACTION_SNOOZE -> {
				HydrationReminderScheduler.snooze(context)
			}
			Intent.ACTION_BOOT_COMPLETED -> {
				HydrationReminderScheduler.scheduleNext(context)
			}
		}
	}
}
