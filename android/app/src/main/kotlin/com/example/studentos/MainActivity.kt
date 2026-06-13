package com.example.studentos

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val CHANNEL = "studentos/notification_service"
	private val ACADEMIC_ALERT_CHANNEL_ID = "academic_alerts"
	private val PREFS = "studentos_prefs"
	private val DONT_ASK_KEY = "notification_dont_ask"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"checkPermission" -> {
					val granted = hasNotificationListenerPermission()
					result.success(granted)
				}
				"openSettings" -> {
					openNotificationSettings()
					result.success(true)
				}
				"markDontAskAgain" -> {
					val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
					prefs.edit().putBoolean(DONT_ASK_KEY, true).apply()
					result.success(true)
				}
				"shouldAsk" -> {
					val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
					val dontAsk = prefs.getBoolean(DONT_ASK_KEY, false)
					val granted = hasNotificationListenerPermission()
					result.success(!dontAsk && !granted)
				}
				"getEnabledApps" -> result.success(NotificationFilterStore.getEnabledApps(this).toList())
				"setEnabledApps" -> {
					val apps = call.argument<List<String>>("apps")?.toSet().orEmpty()
					NotificationFilterStore.setEnabledApps(this, apps)
					result.success(true)
				}
				"addEnabledApp" -> {
					val packageName = call.argument<String>("packageName")
					if (packageName.isNullOrBlank()) {
						result.error("invalid_argument", "packageName is required", null)
					} else {
						NotificationFilterStore.addEnabledApp(this, packageName)
						result.success(true)
					}
				}
				"removeEnabledApp" -> {
					val packageName = call.argument<String>("packageName")
					if (packageName.isNullOrBlank()) {
						result.error("invalid_argument", "packageName is required", null)
					} else {
						NotificationFilterStore.removeEnabledApp(this, packageName)
						result.success(true)
					}
				}
				"getWhatsappPeopleWhitelist" -> result.success(NotificationFilterStore.getWhatsappPeopleWhitelist(this).toList())
				"setWhatsappPeopleWhitelist" -> {
					val values = call.argument<List<String>>("values")?.toSet().orEmpty()
					NotificationFilterStore.setWhatsappPeopleWhitelist(this, values)
					result.success(true)
				}
				"addWhatsappPerson" -> {
					val name = call.argument<String>("name")
					if (name.isNullOrBlank()) {
						result.error("invalid_argument", "name is required", null)
					} else {
						NotificationFilterStore.addWhatsappPerson(this, name)
						result.success(true)
					}
				}
				"removeWhatsappPerson" -> {
					val name = call.argument<String>("name")
					if (name.isNullOrBlank()) {
						result.error("invalid_argument", "name is required", null)
					} else {
						NotificationFilterStore.removeWhatsappPerson(this, name)
						result.success(true)
					}
				}
				"getWhatsappGroupsWhitelist" -> result.success(NotificationFilterStore.getWhatsappGroupsWhitelist(this).toList())
				"setWhatsappGroupsWhitelist" -> {
					val values = call.argument<List<String>>("values")?.toSet().orEmpty()
					NotificationFilterStore.setWhatsappGroupsWhitelist(this, values)
					result.success(true)
				}
				"addWhatsappGroup" -> {
					val name = call.argument<String>("name")
					if (name.isNullOrBlank()) {
						result.error("invalid_argument", "name is required", null)
					} else {
						NotificationFilterStore.addWhatsappGroup(this, name)
						result.success(true)
					}
				}
				"removeWhatsappGroup" -> {
					val name = call.argument<String>("name")
					if (name.isNullOrBlank()) {
						result.error("invalid_argument", "name is required", null)
					} else {
						NotificationFilterStore.removeWhatsappGroup(this, name)
						result.success(true)
					}
				}
				"showAcademicAlert" -> {
					val title = call.argument<String>("title") ?: "StudentOS"
					val message = call.argument<String>("message")
					if (message.isNullOrBlank()) {
						result.error("invalid_argument", "message is required", null)
					} else {
						showAcademicAlert(title, message)
						result.success(true)
					}
				}
				else -> result.notImplemented()
			}
		}
	}

	private fun hasNotificationListenerPermission(): Boolean {
		try {
			val contentResolver = applicationContext.contentResolver
			val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
			if (flat == null) return false
			val name = applicationContext.packageName
			return flat.contains(name)
		} catch (e: Exception) {
			Log.e("MainActivity", "Error checking notification listener permission", e)
			return false
		}
	}

	private fun openNotificationSettings() {
		try {
			val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
			intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
			startActivity(intent)
		} catch (e: Exception) {
			Log.e("MainActivity", "Error opening notification settings", e)
		}
	}

	private fun showAcademicAlert(title: String, message: String) {
		try {
			createAcademicAlertChannel()

			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
				checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
			) {
				requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
				return
			}

			val intent = Intent(this, MainActivity::class.java).apply {
				flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
			}

			val pendingIntent = PendingIntent.getActivity(
				this,
				0,
				intent,
				PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
			)

			val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
				Notification.Builder(this, ACADEMIC_ALERT_CHANNEL_ID)
			} else {
				@Suppress("DEPRECATION")
				Notification.Builder(this)
			}

			val notification = builder
				.setSmallIcon(android.R.drawable.ic_dialog_info)
				.setContentTitle(title)
				.setContentText(message)
				.setStyle(Notification.BigTextStyle().bigText(message))
				.setContentIntent(pendingIntent)
				.setAutoCancel(true)
				.build()

			val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
			manager.notify(title.hashCode(), notification)
		} catch (e: Exception) {
			Log.e("MainActivity", "Error showing academic alert", e)
		}
	}

	private fun createAcademicAlertChannel() {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

		val channel = NotificationChannel(
			ACADEMIC_ALERT_CHANNEL_ID,
			"Academic alerts",
			NotificationManager.IMPORTANCE_DEFAULT
		).apply {
			description = "Proactive reminders for quizzes, assignments, exams, and deadlines"
		}

		val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
		manager.createNotificationChannel(channel)
	}
}
