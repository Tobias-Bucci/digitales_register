package it.bucci.digitalesregister

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class DigitalesRegisterWidgetSnapshot(
    val status: String,
    val dashboard: DashboardSection,
    val grades: GradesSection,
    val today: TodaySection,
) {
    fun isReady(): Boolean = status == "ready"

    fun statusMessage(context: Context): String {
        return when (status) {
            "loggedOut" -> context.getString(R.string.widget_state_logged_out)
            "dataSavingDisabled" -> context.getString(R.string.widget_state_data_disabled)
            "appLocked" -> context.getString(R.string.widget_state_locked)
            else -> context.getString(R.string.widget_state_open_app)
        }
    }

    data class DashboardSection(
        val title: String,
        val subtitle: String,
        val emptyMessage: String,
        val items: List<DashboardItem>,
    )

    data class DashboardItem(
        val subject: String,
        val title: String,
        val subtitle: String,
        val dayLabel: String,
        val trailing: String?,
        val warning: Boolean,
        val done: Boolean,
    )

    data class GradesSection(
        val title: String,
        val subtitle: String,
        val emptyMessage: String,
        val overallAverage: String,
        val subjects: List<GradeItem>,
    )

    data class GradeItem(
        val subject: String,
        val average: String,
    )

    data class TodaySection(
        val title: String,
        val subtitle: String,
        val emptyMessage: String,
        val items: List<TodayItem>,
    )

    data class TodayItem(
        val subject: String,
        val timeLabel: String,
        val roomLabel: String,
        val warning: Boolean,
    )
}

object DigitalesRegisterWidgetSnapshotStore {
    fun load(context: Context): DigitalesRegisterWidgetSnapshot? {
        val prefs = context.getSharedPreferences(
            DigitalesRegisterWidgetContract.PREFS_NAME,
            Context.MODE_PRIVATE,
        )
        val raw = prefs.getString(DigitalesRegisterWidgetContract.SNAPSHOT_PREF_KEY, null)
            ?: return null
        return try {
            parse(JSONObject(raw))
        } catch (_: Throwable) {
            null
        }
    }

    private fun parse(root: JSONObject): DigitalesRegisterWidgetSnapshot {
        return DigitalesRegisterWidgetSnapshot(
            status = root.optJSONObject("meta")?.optString("status").orEmpty(),
            dashboard = parseDashboard(root.optJSONObject("dashboard") ?: JSONObject()),
            grades = parseGrades(root.optJSONObject("grades") ?: JSONObject()),
            today = parseToday(root.optJSONObject("today") ?: JSONObject()),
        )
    }

    private fun parseDashboard(section: JSONObject): DigitalesRegisterWidgetSnapshot.DashboardSection {
        return DigitalesRegisterWidgetSnapshot.DashboardSection(
            title = section.optString("title"),
            subtitle = section.optString("subtitle"),
            emptyMessage = section.optString("emptyMessage"),
            items = parseArray(section.optJSONArray("items")) { item ->
                DigitalesRegisterWidgetSnapshot.DashboardItem(
                    subject = item.optString("subject"),
                    title = item.optString("title"),
                    subtitle = item.optString("subtitle"),
                    dayLabel = item.optString("dayLabel"),
                    trailing = item.optNullableString("trailing"),
                    warning = item.optBoolean("warning"),
                    done = item.optBoolean("done"),
                )
            },
        )
    }

    private fun parseGrades(section: JSONObject): DigitalesRegisterWidgetSnapshot.GradesSection {
        return DigitalesRegisterWidgetSnapshot.GradesSection(
            title = section.optString("title"),
            subtitle = section.optString("subtitle"),
            emptyMessage = section.optString("emptyMessage"),
            overallAverage = section.optString("overallAverage"),
            subjects = parseArray(section.optJSONArray("subjects")) { item ->
                DigitalesRegisterWidgetSnapshot.GradeItem(
                    subject = item.optString("subject"),
                    average = item.optString("average"),
                )
            },
        )
    }

    private fun parseToday(section: JSONObject): DigitalesRegisterWidgetSnapshot.TodaySection {
        return DigitalesRegisterWidgetSnapshot.TodaySection(
            title = section.optString("title"),
            subtitle = section.optString("subtitle"),
            emptyMessage = section.optString("emptyMessage"),
            items = parseArray(section.optJSONArray("items")) { item ->
                DigitalesRegisterWidgetSnapshot.TodayItem(
                    subject = item.optString("subject"),
                    timeLabel = item.optString("timeLabel"),
                    roomLabel = item.optString("roomLabel"),
                    warning = item.optBoolean("warning"),
                )
            },
        )
    }

    private fun <T> parseArray(array: JSONArray?, parser: (JSONObject) -> T): List<T> {
        if (array == null) {
            return emptyList()
        }
        return buildList(array.length()) {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                add(parser(item))
            }
        }
    }

    private fun JSONObject.optNullableString(key: String): String? {
        if (isNull(key)) {
            return null
        }
        val value = optString(key)
        return value.takeUnless { it.isEmpty() || it == "null" }
    }
}
