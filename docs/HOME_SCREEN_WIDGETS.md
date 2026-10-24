# Home-screen preparation widgets

Issue: [#33](https://github.com/Tobias-Bucci/digitales_register/issues/33)

Android provides **Dashboard**, **Noten / Grades**, **Heute / Today**, **Schultasche / School bag** and **Hausaufgaben / Homework** in the launcher's widget picker. iPhone and iPad provide the same two widgets through the embedded `PlanningWidgets` WidgetKit extension, in small, medium and large sizes. Tap a widget to open the app's homework dashboard. Labels follow the app language (German, Italian or English; other app languages use German as fallback).

The school-bag widget lists materials by subject, not specific books: the register does not supply a reliable physical book inventory. It deduplicates subjects for the next loaded school day and compares them with the last known school day. Removal advice is qualified as timetable-based and is suppressed for subjects with pending tasks. When homework is unavailable, removal advice is omitted entirely.

Planning uses dated calendar entries, including actual weekend lessons. Missing weekends can be skipped; missing weekdays are unknown and stop planning. Explicit empty days can be skipped, for up to 14 days. Timetables and homework must have a fetch timestamp no older than seven days. There is no repeating-week inference. The widget shows the target date and timetable fetch time. Missing homework produces a warning instead of claiming there are no tasks. Completed, deleted and graded dashboard entries are omitted; calendar assessments supplement the dashboard without reviving completed entries with the same ID.

The existing state-save middleware updates widget data when register data or task completion changes. Privacy restrictions bypass the usual two-second debounce. Native widgets only read a local snapshot: they do not sign in, fetch school data, or store credentials. Open the app to fetch newer data. Planning snapshots expire at local midnight; iOS schedules an empty timeline entry then, and Android checks validity on its periodic refresh. System scheduling may delay refreshes, including clearing a rendered widget after logout; clearing the backing data and requesting a refresh happen immediately in the app.

Logout, account switching, data deletion, disabled data saving and biometric app lock clear or redact preparation data through the existing serialized snapshot service. No account identifiers, teacher names, grades or attachments are exported in the preparation sections. The historical Dart class/channel names still contain `Android` for compatibility. On iOS the shared container receives only the two preparation sections and their validity date, as an atomic, file-protected JSON file excluded from backup. The extension also uses Data Protection and marks content privacy-sensitive.

## iOS signing and verification

The Xcode project includes the extension, its target dependency and its embed phase. All three configurations target iPhone and iPad, starting at iOS 15. Before signing, register/enable `group.it.bucci.digitalesregister.planning` for both the Runner and `it.bucci.digitalesregister.PlanningWidgets` identifiers with the existing development team, and regenerate provisioning profiles if needed. App Group provisioning requires access to the Apple developer account.

On macOS, run `flutter build ios --debug --no-codesign`, then build/archive Runner with Xcode. Check both widget types on iPhone and iPad, including each size, light/dark appearance and larger text. Verify cold/warm taps, task completion, weekend/holiday transitions, missing data, midnight expiry, offline relaunch, account switching, logout and app lock. WidgetKit refreshes should also be checked outside the debugger. Windows cannot compile or run WidgetKit.

Android validation: `android/gradlew.bat :app:compileDebugKotlin :app:processDebugResources`. On a device, add both widgets from the launcher, resize/scroll them and verify the same transitions. The existing RemoteViews collection implementation is retained for compatibility with the other widgets.

References: [Android widget updates](https://developer.android.com/develop/ui/views/appwidgets/advanced), [Apple widget extensions](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension).

## All Android widgets

Dashboard exports upcoming, non-deleted, unfinished entries in date order. Grades uses `Subject.average` and the canonical overall average, including grade weights, cancellations, the selected semester and excluded subjects. Grade colors follow the current shared category helper and the user's color setting. Today displays that date's actual lessons, ordered by period, including times, rooms and substitute warnings; a loaded free day has a different empty state from missing data.

All Android widgets share a compact layout without a separate branding chip. The background follows the device's widget corner radius on Android 12+, uses the standard background view ID and draws an inset outline above the content so the launcher cannot clip off the border. Empty states fill the list area. Rows use smaller corners, consistent spacing and multiline text; grade averages have their own compact row layout. Daily content expires across midnight, and periodic provider updates invalidate the list as well as the header. All exported data sections are redacted when privacy restrictions apply.
