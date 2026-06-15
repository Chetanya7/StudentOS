package com.example.studentos

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Handles the "studentos/health_connect" method channel.
 *
 * Health Connect is conditionally enabled only on Android API 26+.
 * On devices below API 26, all methods return gracefully indicating HC
 * is not available — no crash, no minSdk bump needed.
 */
class HealthConnectChannel(
    private val activity: FlutterActivity
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "HealthConnectChannel"
        private const val HC_PACKAGE = "com.google.android.apps.healthdata"
        private const val REQUEST_CODE_PERMISSIONS = 9001

        val PERMISSIONS = setOf(
            HealthPermission.getReadPermission(StepsRecord::class),
            HealthPermission.getReadPermission(SleepSessionRecord::class),
        )
    }

    private val scope = CoroutineScope(Dispatchers.Main)

    // Pending permission result callback
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkAvailability" -> checkAvailability(result)
            "checkPermissions" -> checkPermissions(result)
            "requestPermissions" -> requestPermissions(result)
            "getSteps" -> getSteps(call, result)
            "getSleepSessions" -> getSleepSessions(call, result)
            "openHealthConnect" -> openHealthConnect(result)
            else -> result.notImplemented()
        }
    }

    // =========================================================================
    // Availability
    // =========================================================================

    private fun checkAvailability(result: MethodChannel.Result) {
        // Require API 26+ for Health Connect
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(mapOf("status" to "unsupportedVersion"))
            return
        }

        val status = HealthConnectClient.getSdkStatus(activity)
        when (status) {
            HealthConnectClient.SDK_AVAILABLE -> {
                result.success(mapOf("status" to "available"))
            }
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> {
                result.success(mapOf("status" to "notInstalled"))
            }
            else -> {
                // Check if HC app is installed
                val installed = isHealthConnectInstalled()
                result.success(mapOf(
                    "status" to if (installed) "available" else "notInstalled"
                ))
            }
        }
    }

    private fun isHealthConnectInstalled(): Boolean {
        return try {
            activity.packageManager.getPackageInfo(HC_PACKAGE, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    // =========================================================================
    // Permissions
    // =========================================================================

    private fun checkPermissions(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(mapOf("granted" to false))
            return
        }

        scope.launch {
            try {
                val client = HealthConnectClient.getOrCreate(activity)
                val granted = client.permissionController.getGrantedPermissions()
                val hasAll = PERMISSIONS.all { it in granted }
                result.success(mapOf("granted" to hasAll))
            } catch (e: Exception) {
                Log.e(TAG, "Error checking permissions", e)
                result.success(mapOf("granted" to false))
            }
        }
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(mapOf("granted" to false))
            return
        }

        // Use the activity result contract
        scope.launch {
            try {
                val client = HealthConnectClient.getOrCreate(activity)
                val granted = client.permissionController.getGrantedPermissions()
                val hasAll = PERMISSIONS.all { it in granted }

                if (hasAll) {
                    result.success(mapOf("granted" to true))
                } else {
                    // Launch Health Connect permission request activity
                    pendingPermissionResult = result
                    val intent = Intent("androidx.health.ACTION_MANAGE_HEALTH_PERMISSIONS")
                        .putExtra(Intent.EXTRA_PACKAGE_NAME, activity.packageName)
                    try {
                        activity.startActivityForResult(intent, REQUEST_CODE_PERMISSIONS)
                    } catch (e: Exception) {
                        Log.e(TAG, "Could not launch HC permission screen", e)
                        pendingPermissionResult = null
                        result.success(mapOf("granted" to false))
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error requesting permissions", e)
                result.success(mapOf("granted" to false))
            }
        }
    }

    /**
     * Call this from the activity's onActivityResult to resolve the permission
     * result back to Flutter.
     */
    fun handleActivityResult(requestCode: Int) {
        if (requestCode != REQUEST_CODE_PERMISSIONS) return
        val pendingResult = pendingPermissionResult ?: return
        pendingPermissionResult = null

        scope.launch {
            try {
                val client = HealthConnectClient.getOrCreate(activity)
                val granted = client.permissionController.getGrantedPermissions()
                val hasAll = PERMISSIONS.all { it in granted }
                pendingResult.success(mapOf("granted" to hasAll))
            } catch (e: Exception) {
                pendingResult.success(mapOf("granted" to false))
            }
        }
    }

    // =========================================================================
    // Steps Data
    // =========================================================================

    private fun getSteps(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(emptyList<Map<String, Any>>())
            return
        }

        val startTime = call.argument<Long>("startTime") ?: run {
            result.error("invalid_argument", "startTime is required", null)
            return
        }
        val endTime = call.argument<Long>("endTime") ?: run {
            result.error("invalid_argument", "endTime is required", null)
            return
        }

        scope.launch {
            try {
                val client = HealthConnectClient.getOrCreate(activity)
                val request = ReadRecordsRequest(
                    recordType = StepsRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(
                        Instant.ofEpochMilli(startTime),
                        Instant.ofEpochMilli(endTime)
                    )
                )
                val response = client.readRecords(request)

                // Aggregate steps by day
                val dailySteps = mutableMapOf<LocalDate, Long>()
                for (record in response.records) {
                    val date = record.startTime.atZone(ZoneId.systemDefault()).toLocalDate()
                    dailySteps[date] = (dailySteps[date] ?: 0L) + record.count
                }

                val records = dailySteps.map { (date, steps) ->
                    mapOf(
                        "date" to date.atStartOfDay(ZoneId.systemDefault())
                            .toInstant().toEpochMilli(),
                        "steps" to steps.toInt()
                    )
                }

                result.success(records)
            } catch (e: Exception) {
                Log.e(TAG, "Error reading steps", e)
                result.success(emptyList<Map<String, Any>>())
            }
        }
    }

    // =========================================================================
    // Sleep Data
    // =========================================================================

    private fun getSleepSessions(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(emptyList<Map<String, Any>>())
            return
        }

        val startTime = call.argument<Long>("startTime") ?: run {
            result.error("invalid_argument", "startTime is required", null)
            return
        }
        val endTime = call.argument<Long>("endTime") ?: run {
            result.error("invalid_argument", "endTime is required", null)
            return
        }

        scope.launch {
            try {
                val client = HealthConnectClient.getOrCreate(activity)
                val request = ReadRecordsRequest(
                    recordType = SleepSessionRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(
                        Instant.ofEpochMilli(startTime),
                        Instant.ofEpochMilli(endTime)
                    )
                )
                val response = client.readRecords(request)

                val records = response.records.map { session ->
                    mapOf(
                        "startTime" to session.startTime.toEpochMilli(),
                        "endTime" to session.endTime.toEpochMilli(),
                    )
                }

                result.success(records)
            } catch (e: Exception) {
                Log.e(TAG, "Error reading sleep sessions", e)
                result.success(emptyList<Map<String, Any>>())
            }
        }
    }

    // =========================================================================
    // Utility
    // =========================================================================

    private fun openHealthConnect(result: MethodChannel.Result) {
        try {
            val intent = activity.packageManager.getLaunchIntentForPackage(HC_PACKAGE)
            if (intent != null) {
                activity.startActivity(intent)
                result.success(true)
            } else {
                // Open Play Store for Health Connect
                val marketIntent = Intent(Intent.ACTION_VIEW,
                    Uri.parse("market://details?id=$HC_PACKAGE"))
                activity.startActivity(marketIntent)
                result.success(true)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error opening Health Connect", e)
            result.success(false)
        }
    }
}
