package it.bucci.digitalesregister

import android.app.Activity
import android.app.Application
import android.os.Bundle
import java.util.Collections
import java.util.WeakHashMap

/**
 * Shared by UI and WorkManager engines in this process. A running job or a
 * foreground service does not mean the app's UI is visible. Never persist this
 * flag: a fresh process after a swipe/crash/reboot starts in the background.
 * All callers and Activity callbacks run on Android's main queue.
 */
object SchoolNotificationVisibility : Application.ActivityLifecycleCallbacks {
    private val visible = Collections.newSetFromMap(WeakHashMap<Activity, Boolean>())

    val isForeground: Boolean
        get() = visible.isNotEmpty()

    override fun onActivityStarted(activity: Activity) { visible.add(activity) }
    override fun onActivityStopped(activity: Activity) { visible.remove(activity) }
    override fun onActivityDestroyed(activity: Activity) { visible.remove(activity) }
    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
    override fun onActivityResumed(activity: Activity) = Unit
    override fun onActivityPaused(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
}
