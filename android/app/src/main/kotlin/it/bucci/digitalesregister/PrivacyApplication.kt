package it.bucci.digitalesregister

import android.app.Application
import android.content.Context
import dev.fluttercommunity.workmanager.BackgroundEngineConfigurator
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterFire's runtime overrides survive process death and take precedence over
 * the manifest. Reset their persisted defaults before any content provider runs.
 * FirebaseInitProvider is removed; Dart initializes Firebase only after this
 * reset and resolution of the versioned decision.
 *
 * These two SDK storage names are deliberately isolated here. Revalidate this
 * compatibility boundary when upgrading the Firebase BoM (see privacy report).
 */
class PrivacyApplication : Application(), BackgroundEngineConfigurator {
    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(SchoolNotificationVisibility)
    }

    override fun configureBackgroundEngine(engine: FlutterEngine) {
        SchoolLocalNotificationsPlugin.install(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "dr/school_notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isForeground" -> result.success(SchoolNotificationVisibility.isForeground)
                    "diagnostics" -> result.success(emptyMap<String, Any>())
                    else -> result.notImplemented()
                }
            }
    }
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        ready = try {
            val crashReset = base.getSharedPreferences("com.google.firebase.crashlytics", MODE_PRIVATE)
                .edit().putBoolean("firebase_crashlytics_collection_enabled", false).commit()
            val analyticsReset = base.getSharedPreferences("com.google.android.gms.measurement.prefs", MODE_PRIVATE)
                .edit().putBoolean("measurement_enabled", false)
                .putBoolean("measurement_enabled_from_api", false).commit()
            crashReset && analyticsReset
        } catch (_: Exception) { false }
    }

    companion object {
        var ready: Boolean = false
            private set
    }
}
