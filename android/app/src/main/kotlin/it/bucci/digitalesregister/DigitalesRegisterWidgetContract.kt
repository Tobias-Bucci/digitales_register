package it.bucci.digitalesregister

import android.app.PendingIntent
import android.content.Context
import android.content.Intent

object DigitalesRegisterWidgetContract {
    const val METHOD_CHANNEL = "dr/android_widgets"
    const val PREFS_NAME = "FlutterSharedPreferences"
    const val SNAPSHOT_PREF_KEY = "flutter.androidWidgetSnapshotV1"
    const val EXTRA_DESTINATION = "widget_destination"
    const val EXTRA_WIDGET_KIND = "widget_kind"

    const val DESTINATION_HOMEWORK = "homework"
    const val DESTINATION_GRADES = "grades"
    const val DESTINATION_CALENDAR = "calendar"

    const val WIDGET_KIND_DASHBOARD = "dashboard"
    const val WIDGET_KIND_GRADES = "grades"
    const val WIDGET_KIND_TODAY = "today"

    fun createLaunchPendingIntent(
        context: Context,
        destination: String,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            action = "it.bucci.digitalesregister.widget.$destination.$requestCode"
            putExtra(EXTRA_DESTINATION, destination)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
