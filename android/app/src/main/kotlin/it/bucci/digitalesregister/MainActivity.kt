package it.bucci.digitalesregister

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationManager
import android.os.PowerManager
import android.provider.Settings
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.CalendarContract
import androidx.activity.enableEdgeToEdge
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private var pendingCalendarPermissionResult: MethodChannel.Result? = null
    private var pendingLaunchDestination: String? = null
    private var widgetMethodChannel: MethodChannel? = null
    private var biometricAppLockChannel: BiometricAppLockChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        pendingLaunchDestination = extractLaunchDestination(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SchoolLocalNotificationsPlugin.install(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dr/school_notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isForeground" -> result.success(SchoolNotificationVisibility.isForeground)
                    "canRequestNotificationPermission" -> result.success(
                        Build.VERSION.SDK_INT >= 33 &&
                        !ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.POST_NOTIFICATIONS))
                    "diagnostics" -> {
                        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val activity = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        val status = mutableMapOf<String, Any>(
                            "batteryOptimized" to !power.isIgnoringBatteryOptimizations(packageName),
                            "powerSaveMode" to power.isPowerSaveMode,
                            "backgroundRestricted" to (Build.VERSION.SDK_INT >= 28 && activity.isBackgroundRestricted)
                        )
                        if (Build.VERSION.SDK_INT >= 26) {
                            status["channelsBlocked"] = listOf("school_grade", "school_message")
                                .any { manager.getNotificationChannel(it)?.importance == NotificationManager.IMPORTANCE_NONE }
                        }
                        val work = WorkManager.getInstance(applicationContext)
                            .getWorkInfosForUniqueWork("it.bucci.digitalesregister.schoolRefresh")
                        work.addListener({
                            try {
                                status["scheduled"] = work.get().any { !it.state.isFinished }
                                result.success(status)
                            } catch (_: Exception) {
                                result.error("scheduler_unavailable", "Background schedule could not be checked", null)
                            }
                        }, ContextCompat.getMainExecutor(this))
                    }
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            android.net.Uri.parse("package:$packageName")))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        biometricAppLockChannel = BiometricAppLockChannel(this).also { channel ->
            channel.register(flutterEngine.dartExecutor.binaryMessenger)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dr/privacy_bootstrap")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Do not initialize a development build with stale generated
                    // Firebase resources from a previously configured build.
                    "ready" -> result.success(PrivacyApplication.ready &&
                        resources.getBoolean(R.bool.firebase_configured))
                    "installationSource" -> {
                        try {
                        val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            packageManager.getInstallSourceInfo(packageName).installingPackageName
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getInstallerPackageName(packageName)
                        }
                        result.success(when (installer) {
                            "com.android.vending" -> "play_store"
                            null -> "manual"
                            else -> "other"
                        })
                        } catch (_: Exception) { result.success("unknown") }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CALENDAR_SYNC_METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestCalendarPermission" -> requestCalendarPermission(result)
                "hasCalendarPermission" -> result.success(hasCalendarPermissions())
                "getDefaultCalendarId" -> result.success(findDefaultWritableCalendarId())
                "getWritableCalendars" -> result.success(listWritableCalendars())
                "upsertCalendarEvent" -> upsertCalendarEvent(call, result)
                "deleteCalendarEvent" -> deleteCalendarEvent(call, result)
                else -> result.notImplemented()
            }
        }
        widgetMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DigitalesRegisterWidgetContract.METHOD_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "refreshWidgets" -> {
                        DigitalesRegisterWidgetUpdater.refreshAllWidgets(applicationContext)
                        result.success(null)
                    }
                    "consumeLaunchDestination" -> {
                        val destination = pendingLaunchDestination
                        pendingLaunchDestination = null
                        result.success(destination)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Native cleanup precedes Dart startup and never changes read state.
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        for (alert in manager.activeNotifications) {
            val channel = if (Build.VERSION.SDK_INT >= 26) alert.notification.channelId else null
            val group = alert.notification.group
            if (channel == "school_grade" || channel == "school_message" ||
                group?.matches(Regex("^school_[a-f0-9]{64}$")) == true) {
                manager.cancel(alert.tag, alert.id)
            }
        }
    }

    override fun onDestroy() {
        biometricAppLockChannel?.dispose()
        biometricAppLockChannel = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val destination = extractLaunchDestination(intent) ?: return
        pendingLaunchDestination = destination
        widgetMethodChannel?.invokeMethod(
            "onLaunchDestination",
            mapOf("destination" to destination),
        )
    }

    private fun requestCalendarPermission(result: MethodChannel.Result) {
        if (hasCalendarPermissions()) {
            result.success(true)
            return
        }

        if (pendingCalendarPermissionResult != null) {
            result.error("permission_pending", "A calendar permission request is already in progress.", null)
            return
        }

        pendingCalendarPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(
                Manifest.permission.READ_CALENDAR,
                Manifest.permission.WRITE_CALENDAR,
            ),
            CALENDAR_PERMISSION_REQUEST_CODE,
        )
    }

    private fun upsertCalendarEvent(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val calendarId = call.argument<Int>("calendarId")
        val title = call.argument<String>("title")
        val description = call.argument<String>("description")
        val startMillis = call.argument<Long>("startMillisUtc")
        val endMillis = call.argument<Long>("endMillisUtc")
        val eventId = call.argument<Int>("eventId")

        if (calendarId == null || title == null || description == null || startMillis == null || endMillis == null) {
            result.error("invalid_args", "Missing required calendar event arguments.", null)
            return
        }

        if (!hasCalendarPermissions()) {
            result.error("missing_permission", "Calendar permission has not been granted.", null)
            return
        }

        val values = android.content.ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId.toLong())
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DESCRIPTION, description)
            put(CalendarContract.Events.DTSTART, startMillis)
            put(CalendarContract.Events.DTEND, endMillis)
            put(CalendarContract.Events.EVENT_TIMEZONE, "UTC")
            put(CalendarContract.Events.ALL_DAY, 1)
        }

        try {
            val resolver = contentResolver
            val finalEventId = if (eventId != null) {
                val uri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId.toLong())
                val updatedRows = resolver.update(uri, values, null, null)
                if (updatedRows > 0) {
                    eventId.toLong()
                } else {
                    resolver.insert(CalendarContract.Events.CONTENT_URI, values)?.lastPathSegment?.toLongOrNull()
                }
            } else {
                resolver.insert(CalendarContract.Events.CONTENT_URI, values)?.lastPathSegment?.toLongOrNull()
            }

            if (finalEventId == null) {
                result.error("write_failed", "Calendar event could not be saved.", null)
                return
            }
            result.success(finalEventId.toInt())
        } catch (t: Throwable) {
            result.error("write_failed", "Calendar event could not be saved.", t.message)
        }
    }

    private fun deleteCalendarEvent(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val eventId = call.argument<Int>("eventId")
        if (eventId == null) {
            result.error("invalid_args", "Missing event id.", null)
            return
        }

        try {
            val uri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId.toLong())
            contentResolver.delete(uri, null, null)
            result.success(null)
        } catch (t: Throwable) {
            result.error("delete_failed", "Calendar event could not be removed.", t.message)
        }
    }

    private fun hasCalendarPermissions(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        return ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED
    }

    private fun findDefaultWritableCalendarId(): Int? {
        return listWritableCalendars()
            .sortedWith(compareByDescending<Map<String, Any>> { it["isPrimary"] as Boolean }.thenBy { (it["id"] as Int) })
            .firstOrNull()
            ?.get("id") as? Int
    }

    private fun listWritableCalendars(): List<Map<String, Any>> {
        if (!hasCalendarPermissions()) {
            return emptyList()
        }

        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.OWNER_ACCOUNT,
            CalendarContract.Calendars.IS_PRIMARY,
            CalendarContract.Calendars.VISIBLE,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
        )

        val calendars = mutableListOf<Map<String, Any>>()
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            null,
            null,
            null,
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(CalendarContract.Calendars._ID)
            val nameIndex = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME)
            val accountNameIndex = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.ACCOUNT_NAME)
            val ownerAccountIndex = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.OWNER_ACCOUNT)
            val primaryIndex = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.IS_PRIMARY)
            val visibleIndex = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.VISIBLE)
            val accessIndex = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL)

            while (cursor.moveToNext()) {
                val visible = cursor.getInt(visibleIndex) == 1
                val accessLevel = cursor.getInt(accessIndex)
                if (!visible || accessLevel < CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR) {
                    continue
                }
                calendars.add(
                    mapOf(
                        "id" to cursor.getLong(idIndex).toInt(),
                        "displayName" to (cursor.getString(nameIndex) ?: ""),
                        "accountName" to (cursor.getString(accountNameIndex) ?: ""),
                        "ownerAccount" to (cursor.getString(ownerAccountIndex) ?: ""),
                        "isPrimary" to (cursor.getInt(primaryIndex) == 1),
                    ),
                )
            }
        }

        return calendars
            .sortedWith(compareByDescending<Map<String, Any>> { it["isPrimary"] as Boolean }.thenBy { it["id"] as Int })
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CALENDAR_PERMISSION_REQUEST_CODE) {
            return
        }

        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pendingCalendarPermissionResult?.success(granted)
        pendingCalendarPermissionResult = null
    }
    private companion object {
        const val CALENDAR_SYNC_METHOD_CHANNEL = "dr/calendar_sync"
        const val CALENDAR_PERMISSION_REQUEST_CODE = 4821
    }

    private fun extractLaunchDestination(intent: Intent?): String? {
        return intent?.getStringExtra(DigitalesRegisterWidgetContract.EXTRA_DESTINATION)
    }
}
