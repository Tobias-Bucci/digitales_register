package it.bucci.digitalesregister

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.os.SystemClock

object DigitalesRegisterWidgetUpdater {
    fun refreshAllWidgets(context: Context) {
        val started = SystemClock.elapsedRealtime()
        WidgetSyncTrace.log(context, "refresh-all-start", "source=flutter-channel")
        val appWidgetManager = AppWidgetManager.getInstance(context)

        for (provider in listOf(SchoolBagWidgetProvider::class.java, PreparationWidgetProvider::class.java)) {
            val ids = appWidgetManager.getAppWidgetIds(ComponentName(context, provider))
            WidgetSyncTrace.log(context, "provider-refresh", "provider=${provider.simpleName} count=${ids.size}")
            PlanningWidgetProvider.updateWidgets(context, appWidgetManager, ids,
                if (provider == SchoolBagWidgetProvider::class.java)
                    DigitalesRegisterWidgetContract.WIDGET_KIND_SCHOOL_BAG
                else DigitalesRegisterWidgetContract.WIDGET_KIND_PREPARATION)
        }

        val dashboardIds = appWidgetManager.getAppWidgetIds(
            ComponentName(context, DashboardWidgetProvider::class.java),
        )
        if (dashboardIds.isNotEmpty()) {
            WidgetSyncTrace.log(context, "provider-refresh", "provider=Dashboard count=${dashboardIds.size}")
            DashboardWidgetProvider.updateWidgets(context, appWidgetManager, dashboardIds)
        }

        val todayIds = appWidgetManager.getAppWidgetIds(
            ComponentName(context, TodayWidgetProvider::class.java),
        )
        if (todayIds.isNotEmpty()) {
            WidgetSyncTrace.log(context, "provider-refresh", "provider=Today count=${todayIds.size}")
            TodayWidgetProvider.updateWidgets(context, appWidgetManager, todayIds)
        }

        val gradesIds = appWidgetManager.getAppWidgetIds(
            ComponentName(context, GradesWidgetProvider::class.java),
        )
        if (gradesIds.isNotEmpty()) {
            WidgetSyncTrace.log(context, "provider-refresh", "provider=Grades count=${gradesIds.size}")
            GradesWidgetProvider.updateWidgets(context, appWidgetManager, gradesIds)
        }
        WidgetSyncTrace.log(context, "refresh-all-end", "durationMs=${SystemClock.elapsedRealtime() - started}")
    }
}
