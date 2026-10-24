package it.bucci.digitalesregister

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

class SchoolBagWidgetProvider : PlanningWidgetProvider(DigitalesRegisterWidgetContract.WIDGET_KIND_SCHOOL_BAG)
class PreparationWidgetProvider : PlanningWidgetProvider(DigitalesRegisterWidgetContract.WIDGET_KIND_PREPARATION)

open class PlanningWidgetProvider(private val kind: String) : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        updateWidgets(context, manager, ids, kind)
    }

    companion object {
        fun updateWidgets(context: Context, manager: AppWidgetManager, ids: IntArray, kind: String) {
            if (ids.isEmpty()) return
            val snapshot = DigitalesRegisterWidgetSnapshotStore.load(context)
            val section = snapshot?.planningSection(kind)
            val current = snapshot?.planningIsCurrent() == true
            val title = context.getString(if (kind == DigitalesRegisterWidgetContract.WIDGET_KIND_SCHOOL_BAG)
                R.string.widget_school_bag_title else R.string.widget_preparation_title)
            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.widget_collection).apply {
                    setImageViewResource(R.id.widget_icon, if (kind == DigitalesRegisterWidgetContract.WIDGET_KIND_SCHOOL_BAG)
                        R.drawable.ic_widget_school_bag else R.drawable.ic_widget_preparation)
                    setTextViewText(R.id.widget_title, section?.title?.takeIf { it.isNotEmpty() } ?: title)
                    setTextViewText(R.id.widget_subtitle, if (current) section?.subtitle.orEmpty() else "")
                    setTextViewText(R.id.widget_empty, when {
                        snapshot == null -> context.getString(R.string.widget_state_open_app)
                        !snapshot.isReady() -> snapshot.statusMessage(context)
                        !current -> context.getString(R.string.widget_state_outdated)
                        else -> section?.emptyMessage.orEmpty()
                    })
                    val service = Intent(context, WidgetCollectionRemoteViewsService::class.java).apply {
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                        putExtra(DigitalesRegisterWidgetContract.EXTRA_WIDGET_KIND, kind)
                        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
                    }
                    setRemoteAdapter(R.id.widget_list, service)
                    setEmptyView(R.id.widget_list, R.id.widget_empty)
                    val launch = DigitalesRegisterWidgetContract.createLaunchPendingIntent(
                        context, DigitalesRegisterWidgetContract.DESTINATION_HOMEWORK, id)
                    setOnClickPendingIntent(R.id.widget_root, launch)
                    setPendingIntentTemplate(R.id.widget_list, launch)
                }
                manager.updateAppWidget(id, views)
            }
            manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
        }
    }
}
