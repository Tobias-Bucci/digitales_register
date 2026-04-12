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

    override fun getCount(): Int {
        val current = snapshot
        if (current == null || !current.isReady()) {
            return 0
        }
        return when (widgetKind) {
            DigitalesRegisterWidgetContract.WIDGET_KIND_GRADES -> current.grades.subjects.size
            DigitalesRegisterWidgetContract.WIDGET_KIND_TODAY -> current.today.items.size
            else -> current.dashboard.items.size
        }
    }

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_list_item)
        val current = snapshot
        if (current == null || !current.isReady()) {
            return views
        }

        when (widgetKind) {
            DigitalesRegisterWidgetContract.WIDGET_KIND_GRADES -> {
                val item = current.grades.subjects[position]
                views.setTextViewText(R.id.widget_item_primary, item.subject)
                views.setTextViewText(R.id.widget_item_secondary, item.average)
                views.setTextViewText(R.id.widget_item_meta, context.getString(R.string.widget_average_label))
                views.setInt(
                    R.id.widget_item_primary,
                    "setTextColor",
                    ContextCompat.getColor(context, R.color.widget_text_primary),
                )
            }

            DigitalesRegisterWidgetContract.WIDGET_KIND_TODAY -> {
                val item = current.today.items[position]
                views.setTextViewText(R.id.widget_item_primary, item.subject)
                views.setTextViewText(R.id.widget_item_secondary, item.timeLabel)
                views.setTextViewText(R.id.widget_item_meta, item.roomLabel)
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
                val item = current.dashboard.items[position]
                views.setTextViewText(R.id.widget_item_primary, item.subject)
                views.setTextViewText(R.id.widget_item_secondary, item.title)
                val meta = buildString {
                    append(item.dayLabel)
                    if (item.trailing != null) {
                        append("  •  ")
                        append(item.trailing)
                    }
                    if (item.subtitle.isNotEmpty()) {
                        append("  •  ")
                        append(item.subtitle)
                    }
                }
                views.setTextViewText(R.id.widget_item_meta, meta)
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

    override fun hasStableIds(): Boolean = true
}
