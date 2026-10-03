> Update 2026-10-03: privacy notice version **5** removes the age question, age gating and age storage for new decisions. Explicit purpose consent, default-off startup and platform safeguards remain. The redesigned dialog integrates details and customization into its content and emphasizes the allow-all action. Existing decisions require a new explicit choice. Verification: 337 tests passed, including 24 dialog layout cases; analysis found no issues. The report and v4 audit below describe the earlier implementation.

> Previous privacy audit: [PRIVACY_AUDIT_V4.md](PRIVACY_AUDIT_V4.md). Data inventory and manual cloud tasks are maintained separately.

> Dialog follow-up 2026-10-03: unsaved purpose choices start selected; saving accepts the current selection, while reopening settings preserves saved choices. The title is one short localized word, without the header icon or update wording. About now uses a compact theme-based dialog with expandable project/license details. 65 dialog/settings tests passed and analysis found no issues.

# Analytics implementation report — Digitales Register

Implemented 2026-09-30; privacy hardening reviewed 2026-10-01. Current privacy notice version: **4**. No Firebase Console settings, live BigQuery queries or real-device delivery checks were performed. Companion documents: [Console configuration](FIREBASE_ANALYTICS_CONSOLE_CONFIGURATION.md), [BigQuery examples](ANALYTICS_BIGQUERY_EXAMPLES.md), [school reservations](analytics_school_mapping.csv).

## A. Summary

Extended the existing privacy controller, diagnostics gate, native default-off bootstrap, consent dialog, details page and Settings. There is one authoritative privacy record, three stored purpose choices and local-only coarse age eligibility. Product Analytics now has a centralized service, strict schemas, installation-local account UUIDs, nine custom user properties, explicit navigation/action/load/sync instrumentation and separately gated academic snapshots. No raw school-register content, credentials or individual grades pass through the application Analytics boundary.

Local verification: **302 tests pass**, Android debug/release APKs and Windows debug build succeed. Analysis has no errors/warnings and 19 pre-existing informational lints. Apple structures were inspected; Apple builds and real Firebase delivery remain unverified on this Windows host. Read all limitations before publishing.

## B. Existing Analytics found before changes

`analytics_service.dart` was a static facade around the existing PrivacyController. Version 3 used unknown/requiredOnly/allAllowed and enabled Analytics/Crashlytics together. Initialization checked the native bootstrap bridge and used Firebase.initializeApp without firebase_options.dart; no generated options file was found. Android local Google Services/variant configuration already existed. Native default-off flags, advertising consent denial and automatic screen disablement existed.

Seven legacy custom names were allowlisted: app_first_frame, theme_loaded, app_opened, calendar_viewed, grade_calculator_added_grade, grade_calculator_imported_grades and login_attempt. Only integer elapsedMs/count inputs were accepted. Screens used the sanitized Diagnostics observer. No custom User-ID or user properties existed. The previous privacy work had already removed grade-average tracking. Crashlytics handlers, error categories, keys/logs and network sanitizers remain intact.

Inspection covered pubspec/overrides, Firebase/native initialization, consent/services/main/navigation/sidebar, privacy UI/locales, Settings/persistence, authentication/multiple accounts/demo, wrapper/Dio, school catalog, grade models/selectors/calculation, timetable/homework/absences/notifications, calendar sync, native manifests/plists/bootstrap, build channels, tests and the previous audit. The vendored Workmanager package is not a current application dependency/headless Analytics task. No trusted aggregate-serving or Analytics deletion backend was found.

Legacy compatibility methods remain: calculator actions become safe feature_action events, calendar_viewed maps to a timetable screen, and startup/custom login-button timing/count inputs are ignored. Actual login attempts are tracked at the authentication boundary. Automatic Firebase lifecycle events are not duplicated with custom app-open/frame events.

## C. Privacy version migration

The sole currentPrivacyNoticeVersion changed from 3 to 4. isCurrent requires completion at that exact version. Legacy flags, corrupt/incomplete records, version 3-or-older and simulated later versions cannot authorize optional processing. Existing installations receive the update notice; fresh installations receive the normal notice. Saving v4 prevents repetition until another notice version.

Both application gates close synchronously before preferences are read. Native bootstrap resets sticky SDK overrides before initialization. Invalid/current-denied Analytics decisions also reset device Analytics data. Old optional consent is never silently translated. Information and customization views do not persist a decision. One JSON preference entry still atomically stores purpose/version/age choices; legacy v1/v2 flags are removed only after a successful decision write.

## D. Consent model

PrivacyDecision adds ConsentChoice { denied, granted } for diagnosticsConsent, usageAnalyticsConsent and academicStatisticsConsent, and AnalyticsAgeEligibility { unknown, atLeast14, under14 }. Existing version, completed, UTC timestamp and reportsPurged remain. Serialized privacyNoticeVersionAccepted/consentDecisionTimestamp preserve existing persistence names. Legacy telemetryConsentState is compatibility/migration data only; current convenience states are derived from the granular record.

| Predicate | Requirements |
|---|---|
| diagnosticsAllowed | Current v4 + atLeast14 + diagnostics granted |
| analyticsAllowed | Current v4 + atLeast14 + usage granted |
| academicStatsAllowed | analyticsAllowed + academic granted |
| allOptionalAllowed | diagnosticsAllowed + academicStatsAllowed |
| requiredOnly | Neither diagnostics nor usage allowed |

chooseGranular saves all purposes denied for unknown/under14 and denies academic consent when usage is denied. Independent gates support diagnostics-only, usage-only, both and neither. SDK/bootstrap/purge/storage failures fail closed without breaking required functions. SDK failure can temporarily keep both optional SDKs off despite stored permission; the authoritative preference remains available for retry/restart.

## E. Age eligibility implementation

The UI asks only whether the user is at least 14, with Yes/No. No birth date/year, exact age or parent details are stored. The coarse enum stays in local privacy state/UI; it is never sent through Analytics, Crashlytics, backend calls or logs. No fake parental authorization exists.

Allow-all with unresolved eligibility opens the age step. Under14 leaves all optional purposes disabled and explains why. Customization disables switches until eligibility is resolved; academics additionally require usage. Settings can reopen eligibility. A manual eligibility change immediately closes both optional gates, persists local eligibility with all purposes denied, resets optional drafts to off and still requires an explicit purpose decision. Only completing the explicit allow-all action after Yes can allow all purposes.

## F. Firebase Analytics runtime configuration

AnalyticsService owns one PrivacyController and one ProductAnalytics. _FirebaseCollection preserves native readiness/platform checks. On withdrawal it stops native collection before clearing SDK identity/properties and denying storage; on opt-in it sets all Consent Mode signals before enabling collection. Initialization failures are cached for the process. Analytics storage is true only for current eligible usage consent. Ad storage, ad user data and ad personalization signals are always false.

Revocation closes the Dart gate synchronously. Queued event/identity/property/snapshot work is fenced by an epoch so old consent/account sessions are discarded. User-ID and all nine custom properties clear, collection/storage consent deny, and resetAnalyticsData runs. In-flight SDK work already accepted cannot be undone; uploaded history is not automatically deleted. Valid opted-in startup pauses collection and clears account attribution for safe reidentification without resetting app-instance data. Academic revocation alone blocks academic submission while allowed usage can resume.

Automatic screens remain off. No ads integration, advertising ID, remarketing, Performance Monitoring or additional Firebase product was added. Apple Podfiles choose the existing FlutterFire Analytics Core/no-ad-ID option; plists explicitly deny Analytics storage by default. Android advertising permission removals and bootstrap are preserved. Console links/sharing/retention require manual review.

## G. Analytics user identity

Selected **C: installation-local UUID**, separated per saved local account. Wrapper/config has a numeric school/student account identifier, unsuitable as a trusted globally opaque Analytics ID. No first-party Analytics UUID issuer exists. No username/email/student ID is encoded or hashed into uploaded User-ID.

Random.secure generates UUIDv4 values. A local lookup key (register URL + username) is used solely inside existing encrypted storage to associate saved accounts with random UUIDs; it never reaches Firebase/logs/properties/events. Identity source installation_uuid stays local. A random preferences-backed namespace scopes encrypted identity/snapshot entries so a Keychain entry surviving uninstall is not reused by a fresh install without restored preferences. Restoring app data may restore an identity; it is not a verified person identifier.

User-ID is set only under eligible current usage consent. Switching invalidates queued account work, clears old SDK attribution and establishes the new UUID before academics. Logout preserves global consent/device preferences but clears active account properties and in-memory snapshot associations. Saved UUIDs/successful fingerprints remain local so returning to the same local account does not re-emit an unchanged summary. Storage corruption/errors omit optional identification rather than falling back to unsafe IDs.

## H. School ID implementation

The actual catalog has **229 entries**. analytics_school_ids.dart reserves one explicit unique school_0001…school_0229 ID per entry. These are immutable literals, not runtime indices, hashes, display names or URLs. Reordering cannot change them. Renames must move the same reservation with the school; new IDs are appended and retired IDs never reused.

The developer-only CSV contains analytics_id, school_display_name and technical_provider_identifier_if_safe (public provider URL), with no user/student data. It is never uploaded. The app persists the register URL rather than a disambiguating school selection. Three URLs are shared by pairs of catalog entries: ambiguous/custom/unknown URLs resolve to null rather than a guessed school. Academic submission is omitted for unresolved associations. Demo always has null school association.

## I. User properties

Names/values are centrally validated; invalid strings are rejected rather than truncated. All require usage consent. school_id additionally requires academic consent and non-demo mode at the central property boundary. All clear on usage revocation; account properties additionally clear on logout/switch.

| ID | Firebase name | Source | Example | When set | When cleared |
|---|---|---|---|---|---|
| UP01 | school_id | Explicit unambiguous catalog reservation | school_0037 | Signed-in mapped non-demo context with academic consent | Logout/switch, demo/unknown school, usage or academic revoke |
| UP02 | school_api_type | Existing provider/demo mode | digital_register_api | Safe signed-in context | Logout/switch/revoke |
| UP04 | demo_mode | AppState.isDemo | false | Signed-in context/change | Logout/switch/revoke |
| UP05 | app_language | Settings, lld normalized to ld | de | Consent context/language change | Revoke |
| UP06 | theme | Existing theme preference | system | Context/theme change | Revoke |
| UP07 | academic_year | schoolYearForDate(now) | 2026_2027 | Signed-in context | Logout/switch/revoke |
| UP08 | build_flavor | Existing BUILD_FLAVOR define | production | Authorized context | Revoke |
| UP09 | release_channel | Debug/RELEASE_CHANNEL define | debug | Authorized context | Revoke |
| UP10 | notifications_enabled | ProfileState.sendNotificationEmails | true | Signed-in known profile/change | Logout/switch/revoke |

UP03 user_role is omitted: isStudentOrParent cannot distinguish a reliable role. UP11 school_type is omitted: no categorical catalog field exists. Missing build/channel defines stay unknown; arbitrary strings are rejected. Notification-enabled means the actual register-email preference used by the app, not OS push permission or a logged-in proxy. No age/gender/class/teacher/subject/grade/average/attendance/interest properties exist.
## J. Events

Definitions live in analytics_schema.dart. Unknown names/keys/values are rejected. Application SDK calls are confined to analytics_service.dart; producers call the central abstraction. All normal events require current usage consent and eligible age (U). Academics additionally require academic consent (A), a safe identity, mapped school and non-demo mode. No custom default-event parameters exist.

| Event | Parameters | Actual trigger | Consent | Frequency |
|---|---|---|---|---|
| screen_view | Stable screen_name, constant register_screen class | Sanitized navigator/known feature navigation | U | Consecutive-screen dedup |
| login_attempt | login_provider | Actual login action | U | Each attempt |
| login_result | result, login_provider | Online completion or failure action | U | Each outcome; unknown for untyped failures |
| logout | reason | Logout/add-account/removal after attribution clears | U | Boundary |
| feature_opened | feature, source | Known routing actions | U | Navigation |
| feature_action | feature, action | Calculator add/import, homework toggle, mark-read, timetable/grade view/history actions | U | Explicit action |
| refresh_requested | feature, source | Existing high-level feature loads | U | Bounded category |
| refresh_result | feature, result, data_source, duration_bucket | Coalesced load cache-success marker, actual grade fetch, exceptions, synthetic helper | U | Bounded result |
| sync_started | sync_type | Existing serialized calendar operation | U | Bounded start |
| sync_completed | sync_type, result, duration_bucket | Calendar operation completion/failure | U | Bounded result |
| semester_changed | semester | Grade semester action | U | Change |
| tab_changed | feature, tab_id | Chart/history logical subview opening | U | Explicit view |
| filter_changed | feature, filter_id | Homework future/past change | U | Change |
| sort_changed | feature, sort_id | Grade type/date sorting preference | U | Change |
| notification_opened | notification_type | Existing notification-to-message action; general only | U | Open |
| notification_settings_changed | enabled | Actual register email-notification preference | U | Change |
| theme_changed | theme | Existing theme preference setter | U | Change |
| language_changed | language | Existing settings language action | U | Change |
| demo_mode_changed | enabled | Observed demo-state transition | U | Transition |
| cache_result | feature, result | Runtime-cache/coalesced load/grade cache boundary | U | Bounded category |
| data_source_used | feature, data_source | Loaded action/verified cache hit; demo is local | U | Bounded category |
| calendar_sync_changed | enabled | Calendar sync setting | U | Change |
| calendar_sync_result | result, duration_bucket | Serialized calendar completion/failure | U | Operation result |
| onboarding_step | step_id, action | Existing tutorial shown/completed/skipped milestones | U | Milestone |
| error_presented | feature, error_category | Existing error UI/observed offline state | U | Coarse presented category |
| permission_result | permission_type, result | Actual native calendar permission result | U | Actual request |
| external_action | action_type | Existing Firebase privacy-info link | U | Explicit open; no URL |
| app_update_observed | previous_version, current_version | Existing version tracking with current startup consent | U | Upgrade, no pre-consent replay |
| offline_usage | feature, action | Feature load with already-observed offline state | U | Boundary; no probe |
| account_switch | None | Selection after attribution clears | U | Explicit switch |
| privacy_settings_changed | action=saved | Confirmed privacy save if usage allowed afterwards | U | Save; no age/choice fields |
| academic_summary_updated | academic_year, semester, grade_average_tenths, grade_count_bucket, subject_count_bucket, snapshot_schema_version | Valid local data/semester/average-settings/consent boundary | U+A | Changed successful snapshot |

Closed enums cover feature/source/action/result/data-source/duration/filter/sort/notification/permission categories. Some allowed values have no current trustworthy signal: rich login failure reasons, fine notification categories, permanent-denial distinctions and external share/export actions are not inferred from text/content. Chart/history are logical subviews, not a claim that a physical TabBar exists. No render/scroll/frame/grade-row/per-retry event was added.

Identical normal payloads have 500 ms debounce. Refresh/cache/data-source/sync payloads have 5-second suppression, with a bounded 128-entry local map. Screen dedup is separate; academics use persistent change dedup rather than action throttling. Dispatcher return can precede grade completion, so grade results are emitted in actual fetch callbacks. Coalesced load success uses its real cache-fresh marker. SDK failures never serialize exception text. The last-events map, elapsed stopwatch values and fingerprints remain local.

## K. Academic statistics

The display selector and Analytics share overallGradeAverage(AppState). It equally averages non-ignored subject averages. Subject.average preserves assessment weights and cancelled-grade exclusion. Grades are represented in hundredths; app numeric validation is 0–1000, corresponding to 0–10. No alternative formula was introduced. Contributions reflect the current local period and ignored-subject preferences, not an official report-card result.

Only the overall value leaves the device: multiply by ten and round to an integer, e.g. 8.1 -> 81. Invalid/out-of-range/nonfinite values, empty/noncontributing grades/subjects, missing subject data, unmapped schools and grades outside the current school year are omitted. Existing schoolYearForDate has a July boundary; September 2026 becomes 2026_2027. No calendar-year shortcut was introduced. Semester is 1/2/year. Year snapshots follow currently available app year data, not guaranteed final-year completeness.

Grade buckets: 0, 1_5, 6_10, 11_20, 21_40, 41_plus. Subject buckets: 0, 1_5, 6_10, 11_plus. Empty buckets are not submitted because no valid average exists. No named grading_scale is sent because there is no reliable scale-category field. Dates, names, grades and per-subject averages stay local.

A canonical normalized serialization is the local fingerprint, scoped by UUID/school/year/semester and stored in encrypted storage. No fingerprint is transmitted. Unchanged summaries are skipped across screens/restarts; changed normalized summaries emit again. Save only after the SDK log call succeeds, leaving failures retryable. SDK success is local acceptance, not a server-delivery receipt. Local semester ownership must match the active account: late responses from another account cannot contribute, and cached-only grades without current-session fetch provenance are omitted until a fresh fetch establishes ownership. Invalid negative numeric grade weights are rejected. Epoch checks discard old account/consent work. Demo is excluded from normal and developer academic helpers.

Correct aggregation selects one latest valid row per User-ID/year/semester before averaging, takes school from the same event, counts distinct pseudonymous IDs and suppresses every displayed cohort below 30. This engineering threshold is not a legal anonymity guarantee. Overall reports must include participant count. No annual popup/public statistic/ranking was implemented without a trusted backend.

## L. Data explicitly excluded

No passwords/access/refresh tokens, session cookies, authorization/Bearer headers, usernames, email/real/student/teacher names, raw school account/student IDs, exact class/section or school display names. No individual grades, subject names/averages, teacher IDs, homework/messages, attendance counts/days/reasons, sickness/health/disciplinary data, free notes/searches, notification titles/bodies, API request/response bodies, raw URLs/queries, precise app timestamps, GPS, Wi-Fi SSID/BSSID or app-added advertising IDs. Age stays local. The reduced overall academic average is the sole permitted performance value and requires its separate purpose choice.

SDK-provided technical/session/app/OS/device/engagement data are distinct from custom fields. The privacy page does not promise that Firebase receives only the nine custom properties. No claim of anonymous contributions or automatic server deletion is made.

## M. Privacy UI changes

The existing dialog/cards/details style was extended. Quick actions are required-only, allow-all, customize and learn more. Required-only denies every purpose. Allow-all resolves age first. Customization uses off-by-default draft switches and explicit save; information/back/customize alone creates no consent. Pending startup cannot be dismissed accidentally; Settings management can be cancelled. Double-save is guarded and persistence errors are retryable.

German, Italian and English catalogs include new text. New Ladin privacy text uses the existing German fallback; it is not claimed as a verified Ladin translation. Details explain pseudonymous identity, installation-counting limits, internal school IDs, reduced averages/buckets, automatic versus app metadata, exclusions, age, control and historical-data limits. No legal guarantee is added.

## N. Settings changes

Settings > Datenschutz & Daten shows each purpose's title/explanation/current state, coarse age status and under14 explanation. Purpose/change rows open the same authoritative form; no parallel store exists. Granular switches remain disabled for unknown/under14, and academics require usage. Details remain available. Reopening/changing eligibility never automatically enables optional purposes.
## O. Files added/changed

Added: lib/product_analytics.dart, lib/analytics_schema.dart, lib/analytics_school_ids.dart; test/product_analytics_test.dart, test/privacy_granular_ui_test.dart; docs/ANALYTICS_IMPLEMENTATION.md, docs/FIREBASE_ANALYTICS_CONSOLE_CONFIGURATION.md, docs/ANALYTICS_BIGQUERY_EXAMPLES.md and docs/analytics_school_mapping.csv.

Extended: lib/privacy_consent.dart, lib/analytics_service.dart, lib/main.dart, lib/app_selectors.dart, lib/middleware/middleware.dart, lib/middleware/grades.dart, lib/calendar_sync_service.dart, lib/theme_controller.dart, lib/tutorial/tutorial_service.dart, lib/container/grades_history_container.dart, lib/ui/notifications_page.dart, lib/ui/privacy_data_details_page.dart, lib/ui/settings_page_widget.dart; four locale catalogs; Apple plists and Podfiles; test/privacy_consent_test.dart, test/privacy_ui_test.dart; docs/PRIVACY_IMPLEMENTATION.md (v4 addendum preserving history).

No test was deleted. No unrelated app formatting changes are retained. Crashlytics handlers/network sanitization/native bootstrap remain intact.

## P. Dependencies

No Dart/Firebase dependency was added/upgraded. Existing Firebase Core/Analytics/Crashlytics, shared_preferences and flutter_secure_storage are reused, including the desktop encrypted-storage adapter. Local firebase_analytics supports the required consent/reset APIs. Apple Podfiles select its existing no-ad-ID dependency option; resolve CocoaPods on macOS. No generated built_value model changed, so code generation is unnecessary. flutter pub get passed; dependency-update notices were not acted on.

## Q. Tests

All **302 tests pass**. Existing privacy tests now make explicit eligible granular choices rather than unsafe implicit full grants. Added coverage: private/free-text/unknown schema rejection; school coverage/unique IDs/format and ambiguous URLs; v3 required/full migration and simulated later notice; independent diagnostics/usage combinations; under14 enforcement; UUIDv4 shape/stability/account separation; queued revocation/property clearing; academic identity/school/consent/demo gates; snapshot restart/change dedup; failed submission retry; precision/range/extra-field rejection; screens/debug helpers and bucket/year validation; late foreign-account data ownership; immediate age denial and age confirmation without purpose grants.

Widget tests cover customization without saving, unknown/under14 disabled switches, allow-all age resolution/No, age choice without automatic grants, existing learn-more/back/save/reopen and phone-size details in all supported locales/light/dark. Existing selector, persistence, account removal/login, grade, calendar sync and other regressions remain. Fakes verify application orchestration, not Firebase servers. Real-device delivery/traffic remain manual.

## R. Build results

| Check | Result |
|---|---|
| flutter pub get | Passed |
| Dart formatting | Modified Dart formatted |
| Generation | Not needed; no generated model changed |
| flutter analyze | No errors/warnings; 19 pre-existing infos; default exit is nonzero for these infos |
| flutter test | Passed: 302 tests |
| Android debug | Passed: build/app/outputs/flutter-apk/app-debug.apk |
| Android release | Passed: build/app/outputs/flutter-apk/app-release.apk, approximately 77.2 MB |
| Windows debug | Passed: build/windows/x64/runner/Debug/DigitalesRegister.exe |
| iOS/macOS | XML/plists, Podfiles, plugin dependency option, bootstrap and Xcode Crashlytics phases inspected; no Apple compile/archive on Windows |

The existing infos concern unrelated UI ordering/braces and the pre-existing tutorial getter/setter. No APK/executable was installed/distributed and no deployment/PR/Console setting was created. Builds do not prove SDK delivery or symbol upload.

## S. Firebase Console manual configuration

Follow the dedicated Console document: verify existing app registrations/linked GA4 property; create the nine real user dimensions, controlled event dimensions and the grade_average_tenths metric; enable daily Analytics BigQuery export if exact latest-participant averages are needed; review retention/sharing/permissions/links; verify devices in DebugView. No Console access/change was performed. Audiences are optional; no key event/conversion is required. Academic statistics must not be advertising conversions/key events.

## T. Custom Definitions

User scopes: school_id, school_api_type, demo_mode, app_language, theme, academic_year, build_flavor, release_channel, notifications_enabled. The Console guide lists the full event scopes for feature/source/provider/result/reason/action/data-source/duration/sync/semester/subview/filter/sort/notification/enabled/theme/language/tutorial/error/permission/external/version/year/buckets/schema. One numeric metric: grade_average_tenths, standard unit. Do not register UUID, school names, unsourced role/type, grades, age or attendance. Do not duplicate standard screen/device/app fields.

## U. BigQuery setup required for exact global averages

The examples document uses GA4 event_params, event user_properties and top-level user_id. It filters real non-demo provider contributions and the synthetic 2099_2100 year, selects the latest valid user/year/semester row with ROW_NUMBER, divides tenths by 10.0, reports overall participant counts and suppresses overall/school groups below 30. It explains daily/intraday duplicates, late arrivals, schema/tie-breaker availability, access/retention/costs and historical revocation limits. Placeholders contain no real project ID. The SQL has not run against a live export.

## V. Limitations

Missing typed failure/role/type/scale sources remain coarse or omitted. Shared/custom URLs reduce academic coverage. User-configured ignored subjects and available year data influence averages. SDK acceptance is not an upload receipt. Multiple changed events require latest-user SQL. There is no verified parent consent, cross-device identity, public aggregate backend, server deletion workflow or performance-statistics UI. These are pseudonymous app-computed contributions, not verified students or official school performance.

## W. Cross-device identity behavior

**Cross-device user deduplication is not available with this fallback.** The same person on two devices may appear as two Analytics users. Different local accounts get different UUIDs; returning to a saved account reuses its UUID while local storage remains. Restored app data can restore identity. No raw/hashed student ID improves matching. Cohort counts refer to pseudonymous IDs, not proven distinct people.

## X. Platform differences

Android uses existing manifest/PrivacyApplication bootstrap and FlutterFire. iOS/macOS retain Apple startup/default-off behavior, adding explicit default-denied Analytics storage and Core/no-ad-ID dependencies. Apple Firebase resources/CocoaPods/archive/dSYMs need macOS verification. Windows/Linux retain local consent/UI/required functions without Firebase collection; Windows debug compiles. No new web support is added to this dart:io app. Future SDK upgrades must revalidate native bootstrap storage-name compatibility.

## Y. Anything still requiring manual verification

Real-device pre-consent traffic/sticky overrides/offline uploads/revocation/restart races; actual User-ID/property clearing and DebugView delivery; Console definitions/retention/sharing/ads links/export; live SQL schema/date ranges/late-arrival behavior/cohort suppression; Apple build/resources/Core dependency resolution/dSYMs; reviewed multilingual privacy language and complete Ladin translation if desired; store privacy declarations and signed distribution configuration. There is no legal guarantee; the 30-ID rule does not make underlying pseudonymous data anonymous.

## Security review

Searched the complete source tree for FirebaseAnalytics, logEvent, logScreenView, setUserId, setUserProperty, setDefaultEventParameters, setAnalyticsCollectionEnabled, setConsent and resetAnalyticsData; SDK calls remain inside the central adapter/native bootstrap. Also searched username/email/name/password/token/Authorization/Bearer/cookie/student/teacher/school/grade/homework/absence/message/request/response/query fields and inspected their potential paths into Analytics. App authentication/provider lookup keys remain local; normal payloads pass closed schemas and academics pass the dedicated summary schema. No direct school-name or individual-grade call exists. Existing app-content networking and manual error UI are not serialized into Analytics. Vendored SDK implementations/tests naturally contain SDK APIs, but application producers use only the central abstraction.

## Manual Firebase Console configuration required

- [ ] Create the nine user dimensions in section I.
- [ ] Create controlled event dimensions from the dedicated guide.
- [ ] Create grade_average_tenths as a standard numeric metric; do not average snapshots as participants.
- [ ] Enable/verify daily Analytics BigQuery export for exact latest-user averages; configure access/region/retention/costs and cohort suppression.
- [ ] Review GA4 retention/activity-reset, sharing/Signals/ads links and exported-data retention separately.
- [ ] Verify consent/age/account/demo scenarios in real-device DebugView; disable debug mode afterwards.
- [ ] Audiences optional, none required; no grade/school advertising audiences.
- [ ] No key events/conversions required; never mark academic statistics as advertising conversions/key events.

Official sources are linked in the Console and BigQuery documents. User-facing copy describes pseudonymous processing and device-side revocation limits, without promising anonymity or automatic server deletion.
