package com.example.studentos

import android.content.Intent
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val CHANNEL = "studentos/notification_service"
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
}
