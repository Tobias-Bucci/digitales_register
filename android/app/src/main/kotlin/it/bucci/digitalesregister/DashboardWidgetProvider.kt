package it.bucci.digitalesregister

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

class DashboardWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        updateWidgets(context, appWidgetManager, appWidgetIds)
    }

    companion object {
        fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray,
        ) {
            val snapshot = DigitalesRegisterWidgetSnapshotStore.load(context)
            for (appWidgetId in appWidgetIds) {
                val views = RemoteViews(context.packageName, R.layout.widget_collection).apply {
                    setTextViewText(
                        R.id.widget_title,
                        snapshot?.dashboard?.title ?: context.getString(R.string.widget_dashboard_title),
                    )
                    setTextViewText(
                        R.id.widget_subtitle,
                        snapshot?.dashboard?.subtitle ?: context.getString(R.string.widget_dashboard_subtitle),
                    )
                    setTextViewText(
                        R.id.widget_empty,
                        when {
                            snapshot == null -> context.getString(R.string.widget_state_open_app)
                            !snapshot.isReady() -> snapshot.statusMessage(context)
                            else -> snapshot.dashboard.emptyMessage
                        },
                    )

                    val serviceIntent = Intent(context, WidgetCollectionRemoteViewsService::class.java).apply {
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                        putExtra(
                            DigitalesRegisterWidgetContract.EXTRA_WIDGET_KIND,
                            DigitalesRegisterWidgetContract.WIDGET_KIND_DASHBOARD,
                        )
                        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
                    }
                    setRemoteAdapter(R.id.widget_list, serviceIntent)
                    setEmptyView(R.id.widget_list, R.id.widget_empty)

                    val launchIntent = DigitalesRegisterWidgetContract.createLaunchPendingIntent(
                        context,
                        DigitalesRegisterWidgetContract.DESTINATION_HOMEWORK,
                        appWidgetId,
                    )
                    setOnClickPendingIntent(R.id.widget_root, launchIntent)
                    setPendingIntentTemplate(R.id.widget_list, launchIntent)
                }
                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
        }
    }
}
