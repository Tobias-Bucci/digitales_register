package it.bucci.digitalesregister

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.CalendarContract
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private var pendingCalendarPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "cancelNotificationSafely" -> {
                    val id = call.argument<Int>("id")
                    if (id == null) {
                        result.error("invalid_args", "Missing notification id.", null)
                        return@setMethodCallHandler
                    }
                    cancelNotificationSafely(id)
                    result.success(null)
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
                "getDefaultCalendarId" -> result.success(findDefaultWritableCalendarId())
                "upsertCalendarEvent" -> upsertCalendarEvent(call, result)
                "deleteCalendarEvent" -> deleteCalendarEvent(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun cancelNotificationSafely(id: Int) {
        NotificationManagerCompat.from(this).cancel(id)
        // The app only shows immediate notifications, so clearing the plugin's
        // scheduled cache is safe and avoids Gson TypeToken crashes on Android.
        getSharedPreferences(SCHEDULED_NOTIFICATIONS_PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(SCHEDULED_NOTIFICATIONS_PREFS)
            .apply()
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
        if (!hasCalendarPermissions()) {
            return null
        }

        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.IS_PRIMARY,
            CalendarContract.Calendars.VISIBLE,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
        )

        val calendars = mutableListOf<CalendarCandidate>()
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            null,
            null,
            null,
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(CalendarContract.Calendars._ID)
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
                    CalendarCandidate(
                        id = cursor.getLong(idIndex),
                        isPrimary = cursor.getInt(primaryIndex) == 1,
                    ),
                )
            }
        }

        return calendars
            .sortedWith(compareByDescending<CalendarCandidate> { it.isPrimary }.thenBy { it.id })
            .firstOrNull()
            ?.id
            ?.toInt()
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

    private data class CalendarCandidate(
        val id: Long,
        val isPrimary: Boolean,
    )

    private companion object {
        const val NOTIFICATION_METHOD_CHANNEL = "dr/notification_background_service"
        const val CALENDAR_SYNC_METHOD_CHANNEL = "dr/calendar_sync"
        const val SCHEDULED_NOTIFICATIONS_PREFS = "scheduled_notifications"
        const val CALENDAR_PERMISSION_REQUEST_CODE = 4821
    }
}
