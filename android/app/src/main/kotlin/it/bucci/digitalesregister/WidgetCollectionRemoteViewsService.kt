package it.bucci.digitalesregister

import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import androidx.core.content.ContextCompat

class WidgetCollectionRemoteViewsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsService.RemoteViewsFactory {
        return WidgetCollectionRemoteViewsFactory(
            applicationContext,
            intent.getStringExtra(DigitalesRegisterWidgetContract.EXTRA_WIDGET_KIND)
                ?: DigitalesRegisterWidgetContract.WIDGET_KIND_DASHBOARD,
        )
    }
}

private class WidgetCollectionRemoteViewsFactory(
    private val context: android.content.Context,
    private val widgetKind: String,
) : RemoteViewsService.RemoteViewsFactory {
    private var snapshot: DigitalesRegisterWidgetSnapshot? = null

    override fun onCreate() {
        snapshot = DigitalesRegisterWidgetSnapshotStore.load(context)
    }

    override fun onDataSetChanged() {
        snapshot = DigitalesRegisterWidgetSnapshotStore.load(context)
    }

    override fun onDestroy() = Unit

    private fun isPlanning(): Boolean = widgetKind == DigitalesRegisterWidgetContract.WIDGET_KIND_SCHOOL_BAG ||
        widgetKind == DigitalesRegisterWidgetContract.WIDGET_KIND_PREPARATION

    override fun getCount(): Int {
        snapshot = DigitalesRegisterWidgetSnapshotStore.load(context)
        val current = snapshot
        if (current == null || !current.isReady()) {
            return 0
        }
        if (widgetKind != DigitalesRegisterWidgetContract.WIDGET_KIND_GRADES && !current.planningIsCurrent()) return 0
        if (isPlanning()) {
            return if (current.planningIsCurrent()) current.planningSection(widgetKind).items.size else 0
        }
        return when (widgetKind) {
            DigitalesRegisterWidgetContract.WIDGET_KIND_GRADES -> current.grades.subjects.size
            DigitalesRegisterWidgetContract.WIDGET_KIND_TODAY -> current.today.items.size
            else -> current.dashboard.items.size
        }
    }

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName,
            if (widgetKind == DigitalesRegisterWidgetContract.WIDGET_KIND_GRADES)
                R.layout.widget_grade_item else R.layout.widget_list_item)
        val current = snapshot
        if (current == null || !current.isReady() || (widgetKind != DigitalesRegisterWidgetContract.WIDGET_KIND_GRADES && !current.planningIsCurrent())) {
            return views
        }

        when (widgetKind) {
            DigitalesRegisterWidgetContract.WIDGET_KIND_GRADES -> {
                val item = current.grades.subjects.getOrNull(position) ?: return views
                views.setTextViewText(R.id.widget_item_primary, item.subject)
                views.setTextViewText(R.id.widget_item_secondary, item.average)
                views.setInt(R.id.widget_item_secondary, "setTextColor", widgetGradeTextColor(context, item.category))
                views.setInt(
                    R.id.widget_item_primary,
                    "setTextColor",
                    ContextCompat.getColor(context, R.color.widget_text_primary),
                )
            }

            DigitalesRegisterWidgetContract.WIDGET_KIND_TODAY -> {
                val item = current.today.items.getOrNull(position) ?: return views
                views.setTextViewText(R.id.widget_item_primary, item.timeLabel)
                views.setTextViewText(R.id.widget_item_secondary, item.subject)
                views.setTextViewText(R.id.widget_item_meta, item.roomLabel)
                views.setViewVisibility(R.id.widget_item_meta, if (item.roomLabel.isBlank()) android.view.View.GONE else android.view.View.VISIBLE)
                views.setInt(
                    R.id.widget_item_primary,
                    "setTextColor",
                    ContextCompat.getColor(
                        context,
                        if (item.warning) R.color.widget_warning else R.color.widget_text_primary,
                    ),
                )
            }

            else -> {
                val items = if (isPlanning()) current.planningSection(widgetKind).items else current.dashboard.items
                val item = items.getOrNull(position) ?: return views
                views.setTextViewText(R.id.widget_item_primary, item.subject)
                views.setTextViewText(R.id.widget_item_secondary, item.title)
                val meta = listOfNotNull(
                    item.dayLabel.takeIf { !isPlanning() && it.isNotBlank() },
                    item.trailing?.takeIf { it.isNotBlank() },
                    item.subtitle.takeIf { it.isNotBlank() },
                ).joinToString(" · ")
                views.setTextViewText(R.id.widget_item_meta, meta)
                views.setViewVisibility(R.id.widget_item_meta, if (meta.isBlank()) android.view.View.GONE else android.view.View.VISIBLE)
                views.setInt(
                    R.id.widget_item_primary,
                    "setTextColor",
                    ContextCompat.getColor(
                        context,
                        when {
                            item.done -> R.color.widget_done
                            item.warning -> R.color.widget_warning
                            else -> R.color.widget_text_primary
                        },
                    ),
                )
            }
        }

        val fillIntent = Intent().apply {
            putExtra(
                DigitalesRegisterWidgetContract.EXTRA_DESTINATION,
                when (widgetKind) {
                    DigitalesRegisterWidgetContract.WIDGET_KIND_GRADES ->
                        DigitalesRegisterWidgetContract.DESTINATION_GRADES
                    DigitalesRegisterWidgetContract.WIDGET_KIND_TODAY ->
                        DigitalesRegisterWidgetContract.DESTINATION_CALENDAR
                    else -> DigitalesRegisterWidgetContract.DESTINATION_HOMEWORK
                },
            )
        }
        views.setOnClickFillInIntent(R.id.widget_item_root, fillIntent)
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
}
