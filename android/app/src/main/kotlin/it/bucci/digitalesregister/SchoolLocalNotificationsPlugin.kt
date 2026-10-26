package it.bucci.digitalesregister

import com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Keep the existing notification plugin, including taps/channels/permissions.
 * Gate only personal school alerts on the native main queue, at the actual
 * show call. This closes the race between Dart's visibility check and show.
 */
class SchoolLocalNotificationsPlugin : FlutterLocalNotificationsPlugin() {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "show") {
            val channel = call.argument<Map<String, Any?>>("platformSpecifics")?.get("channelId")
            if (channel == "school_grade" || channel == "school_message") {
                if (SchoolNotificationVisibility.isForeground) {
                    result.success(null)
                    return
                }
            }
        }
        super.onMethodCall(call, result)
    }

    companion object {
        fun install(engine: FlutterEngine) {
            if (engine.plugins.has(SchoolLocalNotificationsPlugin::class.java)) return
            engine.plugins.remove(FlutterLocalNotificationsPlugin::class.java)
            engine.plugins.add(SchoolLocalNotificationsPlugin())
        }
    }
}
