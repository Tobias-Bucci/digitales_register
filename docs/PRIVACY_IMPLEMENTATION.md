# Privacy and diagnostics implementation audit

Implemented 2026-09-30. Current notice version: **3**. This document records implementation and verification, not a claim that Firebase Console or physical-device checks have been completed.

## A. Summary

Added versioned consent, a consent-gated diagnostics boundary, sanitized technical context, localized data details, and Settings management. Existing required app functions remain usable with optional telemetry disabled. Existing analytics remain gated; the grade-average analytics event was removed. No Performance Monitoring, sensor polling, connectivity probing, user identifiers, or new behavioral Analytics events were introduced.

## B. Consent flow

`privacy_consent.dart` stores one JSON decision in SharedPreferences (`privacyDecision`): accepted notice version, unknown/requiredOnly/allAllowed, completion, UTC decision timestamp, and whether old reports were purged. The central notice constant is 3. Legacy `privacy_consent_choice_v2` and `consent_given` are removed after a successful write.

Fresh installs see the original-style choice dialog. Existing installations with missing, corrupt, incomplete, or older decisions see the update notice. Installation history is inspected before startup writes and persisted so an interrupted first choice does not turn into an existing-user migration. More opens the localized details page and returns without deciding. Pending consent cannot be dismissed accidentally. Double taps are ignored; preference failures permit retry.

Required-only closes the app gate synchronously, disables each SDK independently, attempts deletion of unsent reports, and saves the choice. Grant closes the gate, disables collection, awaits deletion, saves the current choice, enables Crashlytics and Analytics, and opens the gate only when the supported SDK is ready. Purge/SDK failures leave telemetry off. A current granted restart preserves legitimate reports when the saved purge marker is true; it does not delete valid opted-in crash reports each launch. Settings shows persisted status and allows changing the choice or opening details. Incrementing the one notice version invalidates prior choices.

## C. Crashlytics setup

Existing Dart packages resolve to firebase_core 4.11.0, firebase_crashlytics 5.2.4, firebase_analytics 12.4.3. Initialization runs early, is guarded to Android/iOS/macOS, checks native bootstrap readiness, and preserves app operation on SDK failure. Windows/Linux do not invoke Firebase.

Android retains native false collection defaults, disables automatic Analytics screen reporting, removes FirebaseInitProvider eager startup, and uses PrivacyApplication to reset sticky collection overrides before providers can initialize. MainActivity supplies a readiness channel and coarse installer category. The existing Crashlytics Gradle plugin 3.0.2 and Firebase BoM 34.13.0 are retained. Native firebase-crashlytics-ndk was added. Release native symbol upload is enabled, with an optional externally supplied unstripped native library directory.

Apple plists default both collections and advertising consents off and disable automatic screen reporting. Startup resets the sticky Crashlytics setting and disables Analytics before Flutter registration; readiness is exposed through the bootstrap channel. Referenced dSYM upload phases were added to iOS and macOS projects. Apple builds and delivery remain unverified on Windows; both Apple GoogleService-Info.plist files are absent in this checkout.

Native reset code accesses SDK-owned persisted settings because native defaults alone do not override a previous runtime opt-in. This boundary is deliberately isolated, must be reviewed on SDK upgrades, and requires device testing. Relevant official source: [Android arbiter](https://raw.githubusercontent.com/firebase/firebase-android-sdk/master/firebase-crashlytics/src/main/java/com/google/firebase/crashlytics/internal/common/DataCollectionArbiter.java), [Apple arbiter](https://raw.githubusercontent.com/firebase/firebase-ios-sdk/main/Crashlytics/Crashlytics/DataCollection/FIRCLSDataCollectionArbiter.m). See also [Firebase Flutter customization](https://firebase.google.com/docs/crashlytics/flutter/customize-crash-reports).

## D. Error capture

| ID | Implementation |
|---|---|
| E01 | FlutterError.onError, fatal; chains the prior handler. |
| E02 | PlatformDispatcher.onError, fatal; preserves prior handler result. |
| E03 | Explicit worker-isolate listener, fatal; no worker spawn sites currently require attachment. Caller owns/cleans the port. |
| E04 | Caught middleware/application failures, nonfatal, preserving local error behavior. |
| E05 | Dio technical failures, timeouts, bad certificates, unknown errors and 5xx. Expected 401/404/cancellation excluded. |
| E06 | Parser failures through tryParse and transformer FormatException, nonfatal. |
| E07 | Settings/state/cache persistence and corrupt snapshot failures, nonfatal. |
| E08 | Technical authentication failures; ordinary rejected credentials are excluded. |
| E09 | Notification loading/parsing failures; no notification content. |
| E10 | Calendar synchronization/background-operation failures; existing foreground async work only. |

The Firebase sink receives a fixed E-code exception and filtered stack, never the original error text, payload or runtime type. Identity deduplication is bounded to 32 recent errors. Diagnostics failures do not break application operations.

## E. Custom keys

All 45 names are fixed. Dynamic names and invalid enum values are rejected. Booleans/integers are type checked; integer values are bounded. Context updates are deduplicated and only sent while consent is active. Screen/request boundaries and logout reset transient state. Examples below are valid examples, not asserted production values.

| ID | Key | Source / update trigger | Example | Fallback |
|---|---|---|---|---|
| K01 | current_screen | Root observer/sidebar/details navigation | grades | unknown |
| K02 | previous_screen | Actual screen transition | dashboard | unknown |
| K03 | app_state | Existing lifecycle observer | foreground | unknown |
| K04 | demo_mode | Redux authentication/demo state | true | false |
| K05 | logged_in | Redux authentication state | true | false |
| K06 | login_provider | Authentication changes, coarse type | school_api | unknown |
| K07 | api_version | Existing Wrapper API implementation | v2 | v2 |
| K08 | api_environment | Trusted API_ENVIRONMENT build define, startup | production | unknown |
| K09 | api_endpoint | Dio request/response/error, semantic allowlist | /grades | /unknown |
| K10 | http_method | Dio request/response/error | GET | unknown |
| K11 | http_status | Response/error status; reset per request | 500 | 0 |
| K12 | request_type | Safe endpoint category, request start | grades | unknown |
| K13 | response_format | Content type/data kind, response | json | unknown |
| K14 | network_available | Existing offline state and request outcome | true | unknown |
| K15 | connection_type | No reliable existing interface monitor | unknown | unknown |
| K16 | request_retry_count | Request-scoped Zone, retry boundary | 1 | 0 |
| K17 | request_timeout | Dio error; reset per request | true | false |
| K18 | cache_enabled | Existing noDataSaving preference, state updates | true | true |
| K19 | cache_hit | Actual fresh memory/page/register cache access | true | false |
| K20 | local_db_version | No versioned database used by these paths | not_applicable | not_applicable |
| K21 | migration_version | No corresponding database migration schema | not_applicable | not_applicable |
| K22 | semester | Actual existing semester state | 1 | unknown |
| K23 | selected_tab | Actual responsive navigation selection | grades | unknown |
| K24 | selected_filter | Predefined grade/dashboard filter mode | type_sorted | unknown |
| K25 | theme | Theme controller load/change | dark | unknown |
| K26 | locale | Existing locale setting/state | de | unknown |
| K27 | notification_enabled | Existing in-app availability, authenticated state | true | false |
| K28 | notification_type | Coarse existing category, notification operation | general | unknown |
| K29 | background_task | Existing calendar sync start/finally | sync | none |
| K30 | sync_running | Existing serialized sync start/finally | true | false |
| K31 | last_sync_result | Sync completion/failure | partial | unknown |
| K32 | data_source | Actual remote/cache/demo/local operation | cache | unknown |
| K33 | parser | Existing action/request/parse boundary | grades | unknown |
| K34 | feature | Existing action/request feature mapping | authentication | unknown |
| K35 | operation | Existing request/load/save/sync boundary | save | unknown |
| K36 | is_first_launch | Installation history + observed version, startup | true | false |
| K37 | upgrade_detected | Previous vs actual version+build, startup | true | false |
| K38 | previous_app_version | Previously persisted actual package version+build | 2.0.0+42 | unknown; none on fresh install |
| K39 | installation_source | Android installer mapped to coarse category, startup | play_store | unknown |
| K40 | build_flavor | Trusted BUILD_FLAVOR define, startup | staging | unknown |
| K41 | release_channel | Debug mode or trusted RELEASE_CHANNEL define | debug | unknown |
| K42 | flutter_version | Trusted FLUTTER_VERSION define, startup | 3.41.0 | unknown |
| K43 | dart_version | Validated first token of Platform.version, startup | 3.11.0 | unknown |
| K44 | backend_reachable | Normal response/connection failure; no probes | true | unknown |
| K45 | school_api_type | Actual demo vs register API state | digital_register_api | digital_register_api |

K14/K44 describe observed app outcomes, not independent connectivity proof. K27 is in-app availability, not OS push permission. K20/K21 do not refer to privacy notice version. Release channel/flavor are never inferred from user or school identity.

## F. Automatic Crashlytics information

Firebase/platforms provide report time/type, fatality, app/build/package metadata, platform/device/OS/architecture context, SDK installation/session identifiers, execution stacks and platform-dependent native report context. This is automatic SDK information, separate from custom keys; the app does not duplicate hardware identifiers or add sensors. The app never calls setUserIdentifier. Firebase can process transport/network metadata independently of custom app fields; the implementation cannot promise that its service never sees an IP address. See [Firebase privacy information](https://firebase.google.com/support/privacy).

* A19: Android proximity-related native crash context is SDK/platform-specific automatic information. No proximity listener or new permission is added; unavailable elsewhere is not fabricated.
* A25: Native signal/crash information is automatic where the platform SDK supports it, including Apple crash reports and Android NDK reports.
* A26: Applicable on Android because Flutter uses native engine/AOT libraries. Added NDK integration enables native reporting; readable engine/plugin/AOT frames still require matching unstripped symbols. See [NDK setup](https://firebase.google.com/docs/crashlytics/android/get-started-ndk).
* A27: The installed Gradle plugin exposes mapping/native-symbol controls, but no VCS metadata option. No repository URLs, commit author data or invented VCS fields are sent. Current SDK build IDs/mapping metadata remain automatic; requested VCS-specific configuration is not applicable to this installed plugin surface.

## G. Custom logs

Navigation, request/retry/result, login/logout, parser, cache, and sync boundaries emit fixed breadcrumbs such as `screen_opened`, `request_started`, `parser_failed`, `cache_hit`, and `sync_completed`. No values are interpolated. Only the fixed whitelist is accepted; arbitrary messages become `[redacted]`. Nothing is buffered for later upload while disabled. Firebase documents a 64 KB custom-log limit with older entries removed; these compact breadcrumbs use that SDK buffer. See [custom reports documentation](https://firebase.google.com/docs/crashlytics/flutter/customize-crash-reports).

## H. Privacy protection

The sole sink receives allowlisted fields, fixed logs and synthetic E-code errors. It never serializes credentials, cookies, authorization headers, secure storage, Redux state, users, grades, averages, register content, teacher/student names, API bodies or original exception messages. Endpoint normalization replaces URLs with semantic categories and drops hosts, credentials, IDs, fragments and queries. Screen names are fixed. Stack sanitation keeps up to 80 package:/dart: symbol frames and rejects filesystem paths containing developer names. Unsupported values use explicit sentinels. Analytics event parameters are restricted to the existing safe integer count/elapsed values, and screen views use sanitized names. The grade-average event is removed.

The synchronous gate plus epoch invalidation suppresses queued custom work immediately on revocation. Official SDK disable and delete APIs are then awaited. Already uploaded reports cannot be retracted and an SDK/network operation already underway cannot be cancelled by this app gate. Physical-device traffic testing remains necessary, especially for native startup and sticky override compatibility.

## I. Files changed

Added:
* `lib/privacy_consent.dart`: versioned decision/store/controller and launch history.
* `lib/diagnostics_service.dart`: sole sanitized sink, 45 keys, logs, capture, observer, debug helper.
* `lib/diagnostics_network.dart`: Dio technical context/capture interceptor.
* `lib/ui/privacy_data_details_page.dart`: localized responsive details.
* `android/app/src/main/kotlin/it/bucci/digitalesregister/PrivacyApplication.kt`: pre-provider sticky-setting reset.
* `test/privacy_consent_test.dart`: controller/persistence/migration/version cases.
* `test/diagnostics_service_test.dart`: gating/sanitation/dedup/global handler cases.
* `test/diagnostics_network_test.dart`: request metadata and error filtering.
* `test/privacy_ui_test.dart`: consent/details/Settings and locale/theme layout cases.
* `test/privacy_update_ui_test.dart`: existing-user update persistence/no-repeat.
* `docs/PRIVACY_IMPLEMENTATION.md`: this audit report.

Modified:
* `lib/analytics_service.dart`: compatibility facade, SDK startup/consent, safe existing events, decision UI.
* `lib/main.dart`: early initialization, navigation/lifecycle integration.
* `lib/wrapper.dart`: shared Dio interceptor, retry zone, demo/auth/parser context.
* `lib/util.dart`: parser capture without exposing original exception content.
* `lib/middleware/middleware.dart`: Redux context, caught errors, real cache/action boundaries.
* `lib/middleware/notifications.dart`: safe notification type only.
* `lib/container/sidebar_container.dart`: actual sidebar navigation context.
* `lib/theme_controller.dart`: actual preference context.
* `lib/calendar_sync_service.dart`: existing sync context/errors and finally cleanup.
* `lib/page_payload_cache.dart`: actual hit/write/corrupt-storage diagnostics.
* `lib/class_register_cache.dart`: actual hit/write/corrupt-storage diagnostics.
* `lib/state_persistence_service.dart`: safe persistence failures.
* `lib/settings_persistence_service.dart`: safe settings load/save failures.
* `lib/ui/settings_page_widget.dart`: privacy management/status/details card.
* `lib/ui/grades_page.dart`: remove grade-average telemetry.
* `lib/i18n/app_localizations.dart`: deterministic bundled catalog decoding after the enlarged catalog crossed Flutter's isolate threshold.
* `assets/locales/de.json`, `assets/locales/en.json`, `assets/locales/it.json`, `assets/locales/lld.json`: complete localized privacy/settings copy in all four app languages. Ladin privacy text was subsequently translated in full, including the existing consent explanations.
* `android/app/src/main/AndroidManifest.xml`: application/bootstrap/default-off settings and manual screen reporting.
* `android/app/src/main/kotlin/it/bucci/digitalesregister/MainActivity.kt`: readiness and coarse installer channel.
* `android/app/build.gradle`: NDK dependency and native release symbol configuration.
* `ios/Runner/Info.plist`, `macos/Runner/Info.plist`: collection/advertising/screen defaults.
* `ios/Runner/AppDelegate.swift`, `macos/Runner/MainFlutterWindow.swift`: sticky-setting bootstrap and readiness.
* `ios/Runner.xcodeproj/project.pbxproj`, `macos/Runner.xcodeproj/project.pbxproj`: referenced dSYM upload phases.

## J. Dependencies

Only native Android `com.google.firebase:firebase-crashlytics-ndk` was added under the existing BoM. No Dart dependencies were added, changed or removed; pubspec.yaml and pubspec.lock are unchanged. Existing Gradle plugin/BoM versions were retained. No Firebase Performance Monitoring or new connectivity dependency was added.

## K. Tests and commands

* `flutter pub get`: passed.
* `flutter pub run build_runner build --delete-conflicting-outputs`: passed, 43 outputs; current generator warns that the deprecated flag is ignored.
* `dart format` on changed/added Dart files: completed.
* `flutter analyze --no-pub`: zero errors/warnings; 24 existing informational lints in untouched UI/tutorial/container files cause a nonzero exit. No new analyzer diagnostics remain.
* `flutter test --no-pub --reporter expanded`: **283 passed**, including 28 new tests and the 255 existing tests.
* Android debug APK and `flutter build apk --release --no-pub`: passed. Release APK 77 MB.
* `flutter build windows --debug --no-pub`: passed.
* `git diff --check`: passed.
* Merged Android manifest checked: both collection flags false, no FirebaseInitProvider, PrivacyApplication present, NDK registrar present.
* Apple plist parsing/defaults and Xcode phase references structurally checked. This is not Xcode compilation.

New tests cover fresh/required/granted/stale decisions, serialization/corruption, interrupted migration, SDK/purge/persistence failure, retry/double taps, preserving valid reports, queued-work revocation, 45-key allowlisting, sensitive error/stack/URL exclusion, HTTP classification, fatal handler composition, detail back without deciding, Settings reopening, existing-user update/no repeat, and details layouts at phone width in light/dark for de/en/it/lld.

Existing info lint locations: `lib/container/exam_calendar_container.dart`, `lib/tutorial/tutorial_service.dart`, and `lib/ui/{absences_page,calendar_page,calendar_detail_page,class_register_page,course_materials_page,days,exam_calendar_page,homework_summary_page,messages_page,school_countdown_overview_page,sorted_grades_widget}.dart` (import ordering, braces, getter style). See analyzer output for exact existing lines.

## L. Manual actions required

1. Confirm actual Firebase project/app registrations and Analytics/Crashlytics availability in Console. No console access or changes were made. Android configuration already contains production/debug/profile clients; match the installed package.
2. If configuration needs regeneration, run `flutterfire configure --platforms=android,ios,macos` against the existing project and review generated changes so bootstrap/default-off settings are preserved. Add matching Apple GoogleService-Info.plist resources. On macOS run dependency resolution/CocoaPods for both Apple targets, then build/archive in Xcode.
3. Check dSYM phase inputs, sandbox behavior, archive dSYM availability and Console missing-symbol notices on the actual Xcode version. The phase warns/skips absent config/symbols; adding the phase alone is not delivery verification.
4. Test fresh launch, required-only, opt-in, revocation, restart, details/back, old v2 users, and a notice version bump on real Android/Apple devices. Observe Firebase traffic and verify pre-consent cached reports do not appear after grant. Also test native errors before choice and after revocation/restart.
5. In a debug build with current full consent, call `await diagnostics.developerTest()` for a nonfatal report. On Android/iOS `await diagnostics.developerTest(nativeCrash: true)` intentionally crashes; restart and confirm Console fatal/nonfatal reports, keys, breadcrumbs and readable stacks. The helper cannot run in release or without consent; no production button was added.
6. For Android native symbols, supply the actual matching unstripped directory: from `android`, run `./gradlew :app:uploadCrashlyticsSymbolFileRelease -PcrashlyticsNativeSymbolsDir="<UNSTRIPPED_LIBS_DIR>"` (Windows: `./gradlew.bat`). Matching native build IDs and external engine/plugin symbols are required.
7. For Android Dart obfuscation/split-debug-info, retain symbols and run `firebase crashlytics:symbols:upload --app="<FIREBASE_APP_ID>" "<PATH_TO_SPLIT_DEBUG_INFO>"`. The current build does not add obfuscation. For manual iOS dSYM upload, use `ios/Pods/FirebaseCrashlytics/upload-symbols -gsp "<GoogleService-Info.plist>" -p ios "<DSYM_DIRECTORY>"`. See [Flutter setup](https://firebase.google.com/docs/crashlytics/flutter/get-started).
8. Supply trusted build metadata defines when known: FLUTTER_VERSION, BUILD_FLAVOR, RELEASE_CHANNEL, API_ENVIRONMENT. Unspecified values remain unknown. Check Firebase Crash Insights settings if enabled; project-level aggregation settings are not changed by local consent code. Review the user-facing legal copy, including the complete Ladin translation, for linguistic accuracy.

## M. Limitations / platform differences

Android and Windows compile; tests pass. Real-device delivery, offline-cache purge semantics, sticky override startup compatibility, symbol readability and Console state remain manual checks. Apple native code has not been compiled in this Windows environment, and Apple Firebase config/Pods must be completed. macOS follows the Apple bootstrap/configuration path. Windows/Linux retain consent/UI and required behavior without Firebase invocation. No new web support was added to this dart:io-based app.

There are no current worker-isolate sites or headless background tasks to instrument; the reusable worker hook and current async calendar sync are covered. Connection type, uninjected build metadata and Apple installer source remain unknown. Notification-enabled is explicitly existing in-app availability. Shared Crashlytics keys describe latest context; concurrent requests can overwrite that latest context, so they are not guaranteed transaction-bound fields. Strict message/stack filtering trades some debugging detail for privacy. Native fatal SDK reports contain automatic platform metadata outside the custom Dart sanitizer. No claim is made that local revocation deletes already uploaded reports or cancels an upload already in progress.
