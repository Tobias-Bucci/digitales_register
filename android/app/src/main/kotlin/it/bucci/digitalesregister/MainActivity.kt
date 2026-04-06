package it.bucci.digitalesregister

import android.content.Context
import android.os.Bundle
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
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

    private companion object {
        const val NOTIFICATION_METHOD_CHANNEL = "dr/notification_background_service"
        const val SCHEDULED_NOTIFICATIONS_PREFS = "scheduled_notifications"
    }
}
