package it.bucci.digitalesregister

import com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Keep the existing notification plugin, including taps/channels/permissions.
 * Gate only personal school alerts on the native main queue, at the actual
 * show call. This closes the race between Dart's visibility check and show.
 */
class SchoolLocalNotificationsPlugin private constructor(
    private var replaced: FlutterPlugin?,
) : FlutterLocalNotificationsPlugin() {
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        detachReplaced(binding)
        super.onAttachedToActivity(binding)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        detachReplaced(binding)
        super.onReattachedToActivityForConfigChanges(binding)
    }

    /**
     * The stock instance attached to the activity before configureFlutterEngine
     * replaced it. Removing a plugin never unregisters its binding listeners,
     * so the stale instance (channel already null) would still get onNewIntent
     * and crash on every notification tap while the app is alive (#129).
     */
    private fun detachReplaced(binding: ActivityPluginBinding) {
        val stale = replaced ?: return
        replaced = null
        if (stale is PluginRegistry.NewIntentListener) binding.removeOnNewIntentListener(stale)
        if (stale is PluginRegistry.RequestPermissionsResultListener) {
            binding.removeRequestPermissionsResultListener(stale)
        }
        if (stale is PluginRegistry.ActivityResultListener) binding.removeActivityResultListener(stale)
    }

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
            val replaced = engine.plugins.get(FlutterLocalNotificationsPlugin::class.java)
            engine.plugins.remove(FlutterLocalNotificationsPlugin::class.java)
            // add() attaches to the current activity binding, if any, which
            // first drops the replaced instance's listeners from it.
            engine.plugins.add(SchoolLocalNotificationsPlugin(replaced))
        }
    }
}
