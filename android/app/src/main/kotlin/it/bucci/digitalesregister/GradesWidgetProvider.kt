package it.bucci.digitalesregister

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

class GradesWidgetProvider : AppWidgetProvider() {
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
                val views = RemoteViews(context.packageName, R.layout.widget_grades).apply {
                    setTextViewText(
                        R.id.widget_title,
                        snapshot?.grades?.title ?: context.getString(R.string.widget_grades_title),
                    )
                    setTextViewText(
                        R.id.widget_subtitle,
                        snapshot?.grades?.subtitle ?: context.getString(R.string.widget_grades_subtitle),
                    )
                    setTextViewText(
                        R.id.widget_average_value,
                        if (snapshot?.isReady() == true) snapshot.grades.overallAverage else "—",
                    )
                    setTextViewText(
                        R.id.widget_empty,
                        when {
                            snapshot == null -> context.getString(R.string.widget_state_open_app)
                            !snapshot.isReady() -> snapshot.statusMessage(context)
                            snapshot.grades.subjects.isEmpty() -> snapshot.grades.emptyMessage
                            else -> ""
                        },
                    )

                    val serviceIntent = Intent(context, WidgetCollectionRemoteViewsService::class.java).apply {
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                        putExtra(
                            DigitalesRegisterWidgetContract.EXTRA_WIDGET_KIND,
                            DigitalesRegisterWidgetContract.WIDGET_KIND_GRADES,
                        )
                        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
                    }
                    setRemoteAdapter(R.id.widget_list, serviceIntent)
                    setEmptyView(R.id.widget_list, R.id.widget_empty)

                    val launchIntent = DigitalesRegisterWidgetContract.createLaunchPendingIntent(
                        context,
                        DigitalesRegisterWidgetContract.DESTINATION_GRADES,
                        20_000 + appWidgetId,
                    )
                    setOnClickPendingIntent(R.id.widget_root, launchIntent)
                    setPendingIntentTemplate(R.id.widget_list, launchIntent)
                }
                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
        }
    }
}
