# Firebase Console configuration for Digitales Register

This is a manual configuration guide for the version-4 analytics implementation. No Console settings were changed by this implementation. Review this document together with `ANALYTICS_IMPLEMENTATION.md` and `ANALYTICS_BIGQUERY_EXAMPLES.md` before enabling reporting.

## 1. Verify the project and app registrations

Use the existing Firebase project and its linked GA4 property. Check each Android application ID (including debug/profile variants) against its registered app and local Google Services configuration. Do not create a new project just for this change. Apple builds need matching Firebase configuration resources, CocoaPods resolution and device validation on macOS. Windows/Linux do not invoke Analytics or Crashlytics.

Keep automatic screen reporting, advertising identifier collection and all advertising consent disabled. Do not add Google Ads links, Google Signals, remarketing or advertising audiences for this feature. No Firebase Performance Monitoring configuration is needed. Review existing account-level advertising/product links; the Dart changes do not modify Console links.

## 2. Custom user dimensions

In the linked GA4 property's Admin > Data display > Custom definitions, create the following **User-scoped custom dimensions**, using the property name exactly as shown. Console navigation labels can vary by language and account UI. The same definitions are used by Firebase's Analytics reporting.

| Display name | User property | Meaning |
|---|---|---|
| Internal school | `school_id` | Explicit reserved internal ID; never display name |
| Register provider category | `school_api_type` | digital_register_api / demo / unknown |
| Demo mode | `demo_mode` | true / false |
| App language | `app_language` | de / it / en / ld / other |
| Theme preference | `theme` | light / dark / system |
| Academic year | `academic_year` | Existing domain school year, e.g. 2026_2027 |
| Build flavor | `build_flavor` | production / staging / development / unknown |
| Release channel | `release_channel` | production / closed_beta / internal / debug / testflight / unknown |
| Register email notifications enabled | `notifications_enabled` | Existing profile email-notification preference; not an OS push-permission measurement |

There are nine custom properties. Do **not** create `user_role`, `school_type`, exact class, age, grade average or individual-grade user properties. No reliable separate role/type source exists. User-ID is the SDK's pseudonymous `user_id`, not a custom dimension: do not register the UUID as a high-cardinality custom dimension. Do not upload school-name mappings into an event parameter or user property. The mapping CSV stays developer-side.

## 3. Custom event dimensions

Create **Event-scoped custom dimensions** for these parameters when you want them in standard GA4 explorations. They already appear in BigQuery's `event_params` without Custom Definitions; registration makes them available for GA4 UI reporting. Use the exact names. This is a controlled set, not a request to register every automatic SDK field.

| Event parameter | Purpose / example |
|---|---|
| `feature` | grades, timetable, homework, settings, etc. |
| `source` | navigation, automatic, button, etc. |
| `login_provider` | school_api / demo / unknown |
| `result` | Closed result categories appropriate to the event |
| `reason` | Logout category |
| `data_source` | remote / cache / local / mixed / unknown |
| `duration_bucket` | under_250ms ... over_5s |
| `sync_type` | calendar / register / background / unknown |
| `semester` | 1 / 2 / year / unknown |
| `tab_id` | Closed subview identifiers, e.g. chart / history |
| `filter_id` | Closed filters, e.g. future / past |
| `sort_id` | type_sorted / date_sorted |
| `notification_type` | Coarse notification category |
| `enabled` | Normalized 0 / 1 for settings-change events |
| `theme` | light / dark / system |
| `language` | de / it / en / ld / other |
| `action` | Predefined action category |
| `step_id` | Coarse tutorial milestone |
| `error_category` | parsing / offline / unknown, etc. |
| `permission_type` | calendar / notifications (only actual permissions) |
| `action_type` | open_privacy_policy / open_support / share / export / unknown |
| `previous_version` | Sanitized semantic app version |
| `current_version` | Sanitized semantic app version |
| `academic_year` | Academic summary's year |
| `grade_count_bucket` | 1_5 / 6_10 / 11_20 / 21_40 / 41_plus |
| `subject_count_bucket` | 1_5 / 6_10 / 11_plus |
| `snapshot_schema_version` | 1 |

`screen_name` / `screen_class` use the SDK screen-view API and its standard reporting fields: do not create duplicates simply because they are visible in the export. `grading_scale` is deliberately not transmitted or registered: the app has no reliable scale-category field. Some allowlisted values/events are available to the central service but have no current UI trigger; see the implementation report. Do not fabricate activity to populate empty dimensions.

## 4. Custom metrics

Create one **Event-scoped custom metric**:

| Display name | Event parameter | Unit |
|---|---|---|
| Overall grade average in tenths | `grade_average_tenths` | Standard numeric unit |

Do not configure this as currency, revenue, a conversion or a key event. The number 81 represents 8.1. Do not treat its event-level mean/sum in GA4 as a correct participant-level academic average. Participants may submit more than one changed snapshot. Exact latest-per-user reporting requires the BigQuery approach below. Do not create metrics for exact grade counts, subjects, absences or individual grades. Snapshot schema version is a dimension, not a performance metric.

## 5. BigQuery export and aggregate reporting

Enable the existing Analytics property's daily BigQuery export if exact overall/school averages are required. Confirm the destination project's region, access controls, costs, dataset retention and event-export filters. Include `academic_summary_updated`; otherwise the provided query cannot work. Daily export is sufficient for the proposed historical aggregation. Streaming/intraday export is optional and requires additional duplicate/late-arrival handling. Linking is not historical backfill; confirm the available date range before making reports.

Use daily `events_YYYYMMDD` tables; never concatenate daily and intraday copies without deduplication. Apply the provided query with an explicit real academic year and semester. Exclude synthetic 2099_2100 data. Read `user_id`, event parameters and `school_id` from the event's user properties; select one newest snapshot per `user_id + academic_year + semester` **before** averaging. Keep school association from that same selected row. Never count snapshots as participants.

Suppress displayed school/group results with fewer than **30 distinct pseudonymous user IDs**. This is this project's privacy engineering rule, not a universal legal threshold. Display the participant count for overall statistics too. Do not create school/student performance rankings. No public statistics UI or annual popup is included; no trusted aggregate-serving backend was found. Restrict raw exports to authorized developers/analysts.

## 6. Retention, audiences and key events

Review GA4 event/user-data retention and the option that resets retention on new activity; choose the shortest period that supports the approved purpose. Separately review BigQuery dataset/table expiration: GA4 retention settings are not a substitute for controlling exported data. Review permissions and any existing sharing, Signals, advertising or product-link settings. The app does not delete already uploaded history when local consent is revoked, and no automatic server-side deletion workflow was found.

**Audiences:** optional, none required. If used, restrict them to product-function usage and exclude demo/developer data. Do not build grade/school/minor targeting or advertising audiences.

**Key events/conversions:** none required or automatically configured. Academic statistics must never be marked as advertising conversions/key events. There is no product funnel here that needs an obligatory conversion setting.

## 7. DebugView and device verification

On Android, use the actual installed package ID:

```text
adb shell setprop debug.firebase.analytics.app <INSTALLED_PACKAGE_ID>
```

Disable after testing:

```text
adb shell setprop debug.firebase.analytics.app .none.
```

On iOS/macOS, enable the Firebase Analytics debug launch argument `-FIRDebugEnabled` in the development Xcode scheme. Remove it or use `-FIRDebugDisabled` for normal runs. Do not commit production debug-mode settings. Verify the SDK's current platform instructions before shipping an archive.

With **current version-4 consent** and local age eligibility at least 14, invoke from a debugger/development-only harness:

```dart
await AnalyticsService.product.developerTestProductAnalytics();
await AnalyticsService.product.developerTestAcademicAnalytics();
```

The product helper emits `screen_view(analytics_test)`, `feature_opened(analytics_test, unknown)` and `refresh_result(analytics_test, success, local, under_250ms)`. The academic helper requires both analytics choices, a safely initialized identity, a mapped real school and non-demo mode. It uses only synthetic summary values: year 2099_2100, semester 1, average 81, grade bucket 11_20, subject bucket 6_10, schema 1. It never reads the user's grades. It omits a made-up grading scale. The SDK associates the synthetic event with the currently authorized pseudonymous ID/school: exclude its artificial year in every production report. An unchanged synthetic summary is locally deduplicated. These helpers are gated by `kDebugMode` and have no production UI entry point.

Verify these scenarios on real Android and Apple devices:

1. Fresh install and old v3 full/required-only decisions: no optional collection before a v4 decision.
2. Information/customization pages: no decision is created merely by opening them.
3. Diagnostics-only, usage-only, both and neither: verify independence, including restart.
4. Unknown/under14 eligibility: no optional events, no user ID, no school or academic data.
5. Under14 -> atLeast14: all optional choices stay off until explicitly chosen.
6. Usage consent revoked: gate closes, ID and all nine properties clear, collection/consent deny, device Analytics data reset; no subsequent app events.
7. Academic-only revocation: usage may continue but no summary is submitted.
8. Account switch/logout: old identity/properties clear before another account's activity; global consent remains.
9. Demo: product usage allowed with usage consent; no real school ID or academic event.
10. Repeat identical summaries, restart and changed summaries: deduplication and retry behavior match the report.
11. Screen names/parameters/properties: only predefined categories and UUID/internal IDs; no raw content.
12. Revocation while events are queued/offline: verify SDK/device behavior and historical-data limits.

Automated tests and successful builds do not prove Firebase delivery. Verify DebugView, traffic behavior, reporting definitions and export on real devices before publication.

## References checked

- [Firebase Android data collection configuration](https://firebase.google.com/docs/analytics/android/configure-data-collection)
- [Firebase Apple data collection configuration](https://firebase.google.com/docs/analytics/ios/configure-data-collection)
- [Firebase BigQuery export](https://firebase.google.com/docs/projects/bigquery-export)
- [GA4 event export schema](https://support.google.com/analytics/answer/7029846)
- [Firebase Analytics debugging](https://firebase.google.com/docs/analytics/debugview)
- [GA4 custom dimensions](https://support.google.com/analytics/answer/14240153)

The local FlutterFire package was inspected for `setConsent`, `setUserId`, `setUserProperty`, `logScreenView`, `resetAnalyticsData` and platform support. No SDK/API upgrade was introduced.