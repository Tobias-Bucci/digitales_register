package it.bucci.digitalesregister

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context

object DigitalesRegisterWidgetUpdater {
    fun refreshAllWidgets(context: Context) {
        val appWidgetManager = AppWidgetManager.getInstance(context)

        for (provider in listOf(SchoolBagWidgetProvider::class.java, PreparationWidgetProvider::class.java)) {
            val ids = appWidgetManager.getAppWidgetIds(ComponentName(context, provider))
            PlanningWidgetProvider.updateWidgets(context, appWidgetManager, ids,
                if (provider == SchoolBagWidgetProvider::class.java)
                    DigitalesRegisterWidgetContract.WIDGET_KIND_SCHOOL_BAG
                else DigitalesRegisterWidgetContract.WIDGET_KIND_PREPARATION)
        }

        val dashboardIds = appWidgetManager.getAppWidgetIds(
            ComponentName(context, DashboardWidgetProvider::class.java),
        )
        if (dashboardIds.isNotEmpty()) {
            appWidgetManager.notifyAppWidgetViewDataChanged(dashboardIds, R.id.widget_list)
            DashboardWidgetProvider.updateWidgets(context, appWidgetManager, dashboardIds)
        }

        val todayIds = appWidgetManager.getAppWidgetIds(
            ComponentName(context, TodayWidgetProvider::class.java),
        )
        if (todayIds.isNotEmpty()) {
            appWidgetManager.notifyAppWidgetViewDataChanged(todayIds, R.id.widget_list)
            TodayWidgetProvider.updateWidgets(context, appWidgetManager, todayIds)
        }

        val gradesIds = appWidgetManager.getAppWidgetIds(
            ComponentName(context, GradesWidgetProvider::class.java),
        )
        if (gradesIds.isNotEmpty()) {
            appWidgetManager.notifyAppWidgetViewDataChanged(gradesIds, R.id.widget_list)
            GradesWidgetProvider.updateWidgets(context, appWidgetManager, gradesIds)
        }
    }
}
