package it.bucci.digitalesregister

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.SystemClock
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.atomic.AtomicInteger

/** Debug metadata only: never log the snapshot or school/account contents. */
object WidgetSyncTrace {
    private val sequence = AtomicInteger()

    fun log(context: Context, event: String, details: String = "") {
        if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
        val timestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date())
        Log.d("WidgetSync", "$timestamp uptimeMs=${SystemClock.elapsedRealtime()} " +
            "#${sequence.incrementAndGet()} $event $details")
    }
}
