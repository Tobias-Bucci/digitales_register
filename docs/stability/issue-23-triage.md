# Issue #23 – Crash, load-time and memory triage

Status: triage complete, fixes in progress. Refs #23.

## Sources and scope

| Source | Availability |
| --- | --- |
| Crashlytics, Android app `1:750743736341:android:7d14f155234881dde57e1c` (project `digitales-register-ca085`) | Available. Windows of 2026-10-14 → 2026-11-12 (30 days) and 2026-11-05 → 2026-11-12 (7 days). |
| Crashlytics, iOS app `1:750743736341:ios:2d070d4633f6f209e57e1c` | **No data**: the reports API answers 404 for this app (no Crashlytics events received). |
| Windows/Linux/macOS | No Crashlytics (the Windows config is a web app id; desktop does not send crash reports). |
| Firebase Performance Monitoring | **Not integrated** (no `firebase_performance` dependency), so no app-start, frame or network traces exist. |
| Google Play / Android vitals (ANR rate, low-memory kills) | **Not reachable** through the Firebase tools. Crashlytics does not record low-memory kills. |
| Analytics | Not queryable with the available tools. Startup timings below come from Crashlytics breadcrumbs of older builds. |
| GitHub issues | #23 has no extra reports. Related closed issues: #129 (notification tap crash, fixed), #45, #60, #71, #73, #75 (audit crashes, closed). |

Baseline before any change (commit `c6a15767`): `flutter analyze` → no issues; `flutter test` → 3368 passed, 1 skipped, 0 failed.

### Release mix (Android, 30 days, fatal + ANR)

| Version | Track | Users | Fatal/ANR events | Crash-free users |
| --- | --- | --- | --- | --- |
| 1.17.4 (52) | production | 660 | 445 | 52.9 % |
| 1.16.0 (43) | – | 702 | 141 | 90.7 % |
| 1.17.3 (48) | – | 335 | 129 | 74.0 % |
| 2.0.0 (56) | closed beta | 7 | 30 | – |
| 1.13.0, 1.12.0, 1.11.0, 1.10.1, 1.9.3 | – | < 40 each | < 12 each | – |

The low crash-free rate of 1.17.x is almost entirely issue C1 below. Those events are uncaught Dart errors that the app reports as `fatal`. The process keeps running (`PlatformDispatcher.onError` returns `true`), so they are not process deaths.

## Findings

Counts are Android, 30 days (7-day counts in brackets where the issue appeared there). Crashlytics links open the issue in the console.

| ID | Crashlytics issue | Title | Type | Versions | Events / users (7 d) | Severity |
| --- | --- | --- | --- | --- | --- | --- |
| C1 | [5cc051ea](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/5cc051ea371b230a23812ac143ae11c0) | `E02_asyncFatal` / `E01_flutterFatal` at `FirebaseDiagnosticSink.error` | fatal | 1.17.3 – 2.0.0 | 605 / 404 (161 / 118) | critical |
| C2 | [a59457ad](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/a59457ad7fe77ba33268e241748b7261) | `E08_login` at `FirebaseDiagnosticSink.error` | non-fatal | 1.17.3 – 2.0.0 | 3892 / 1829 (1262 / 566) | low (not a crash) |
| C3 | [0a322133](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/0a322133cdcf0065fd3c12ab9e1300ba) | Null check in `_loadGrades.<fn>` (grades.dart) | fatal | 1.9.2 – 1.12.0 | 22 / 18 | high |
| C4 | [d0db287d](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/d0db287de5fd7e3b53de780eb7e87f0f) | Null check in `_loadGradesDetails.<fn>` (grades.dart) | fatal | 1.9.2 – 1.16.0 | 13 / 6 | high |
| C5 | [dc34fd7e](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/dc34fd7e754445c62e0ce4c4b46440f8) | `Infinity or NaN toInt` in `DateTimeScale.reverse` (grade chart) | fatal | 1.13.0 – 1.16.0 | 18 / 14 (1 / 1) | medium |
| C6 | [2d7f8d3b](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/2d7f8d3b8f14e7baa34719fb277944d8) | Null check in `ChartGestureDetector.onScaleEnd` | fatal | 1.13.0 – 1.16.0 | 2 / 2 | low |
| C7 | [9c741071](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/9c7410717b48fffa4ad65f69338bb2c5) | `column 'isPrimary' does not exist` in `_getWritableCalendars` | fatal | 1.16.0 | 16 / 1 | low (blocks calendar sync for affected devices) |
| C8 | [2898a755](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/2898a755085a84efeb155dbf7cf5242d) | NPE in `MainActivity.onNewIntent` (notification tap) | fatal (native) | 1.17.4 – 2.0.0 | 7 / 4 (6 / 3) | high |
| C9 | [03655721](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/0365572123b4d4079cf024083bb829cf) | Null check in `_ProfileState.build` | fatal | 1.9.2 – 1.16.0 | 25 / 7 | – |
| C10 | [7a41318c](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/7a41318c08c42b19f0f579a6423cb073) | Null check in `_GradesChartSelector.select` | fatal | 1.9.2 – 1.16.0 | 20 / 10 (2 / 1) | – |
| C11 | [415adf12](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/415adf1219e9d810c589acb0d4d834b0) | Uncaught `DioException` in `Wrapper._runRequest` from `_refreshSession` | fatal | 1.9.2 – 1.16.0 | 19 / 17 | – |
| C12 | [fed3fa0b](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/fed3fa0bcf2949f7c9f439b923cb3eac) | `ParseException: Missing 'currentUserId='` from `_refreshSession` | fatal | 1.10.1 – 1.12.0 | 19 / 5 (4 / 1) | – |
| C13 | [df6cfabf](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/df6cfabf55942fad49a871c40a254a62) | `RangeError` in `CalendarCardContainer.build` | fatal | 1.10.1 – 1.16.0 | 8 / 1 | – |
| C14 | [53588497](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/53588497cb40c19afbe216ca52ac66a3) | Null check in `ItemWidget.build` (attachment opener) | fatal | 1.13.0 – 1.16.0 | 2 / 1 | – |
| C15 | [8a1a0846](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/8a1a0846c88c6d02d480f863f83d22c3) | `Failed host lookup: '.digitalesregister.it'` | fatal | 1.9.2 – 1.16.0 | 5 / 5 | – |
| C16 | [7ec1fff2](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/7ec1fff22d998a861ff0d1705d05518d) | `E08_login` at `DioMixin.request` | non-fatal | 1.17.0 – 1.17.4 | 2 / 1 | low |
| C17 | [37586cd1](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/37586cd1f4caa7b42f763b33b9538f95) | `E01_flutterFatal` at `Hero._allHeroesFor.inviteHero` | fatal | 1.17.4 | 1 / 1 | low |
| A1 | [4d05f9e7](https://console.firebase.google.com/v1/appid/project/digitales-register-ca085/crashlytics/app/1:750743736341:android:7d14f155234881dde57e1c/issues/4d05f9e74e77520b418eac3a355108f1) | ANR, `MessageQueue.nativePollOnce`, cause unknown | ANR | 1.10.1 – 1.17.4 | 2 / 2 | low |

## Root-cause groups

### G1 – Crash reports lose their stack trace (C1, C2, C16, C17) – `confirmed`

Since 1.17.3 every Dart error goes through `DiagnosticsService.report`. That function passes the stack through `DiagnosticSanitizer.stack`, which keeps only frames that match `(package:…|dart:…):line:column`. Release (AOT) builds print Dart frames **without a column**: the 1.12.0 report C12 shows `#0 Wrapper._readAssignmentValue (package:dr/wrapper.dart:488)`. So the sanitizer drops every frame and hands an empty stack to `FirebaseCrashlytics.recordError`. The plugin replaces an empty stack with `StackTrace.current`. That is the sink itself (`FirebaseDiagnosticSink.error`, `diagnostics_service.dart:54`), which matches every C1/C2 event.

Consequences:
- All uncaught errors since 1.17.3 collapse into a single Crashlytics issue (C1). It cannot be split by cause and has no actionable frame. This explains why 1.17.x shows a 53 % crash-free-user rate while the per-cause issues from older versions stopped appearing.
- C1 events cluster on the grades screen and the login screen (custom keys `current_screen`). The grades samples match the C3/C4 pattern: an offline-first sign-in with the online request still pending or failing, then the grades page opens. Part of C1 is therefore most likely C3/C4, but this cannot be proven from the data.

Evidence: event `6AF5FE25…` (C1, login screen, HTTP 404 HTML), `6AF5F0C9…` and `6AF5E9DD…` (C1, grades screen during a pending/failed online sign-in), and the frame format of `6AF55B06…` (C12).
Local repro: the sign-in middleware was driven against 404, 200 and 500 HTML responses and a connection failure, both online and from storage (8 cases). It raised **no** uncaught error, so the login-screen part of C1 stays `needs more data` until fixed telemetry shows the real frame.

### G2 – Grade loads dereference `config` before the online sign-in loaded it (C3, C4, part of C1) – `confirmed`

`_loadGrades` and `_loadGradesDetails` build the request with `api.state.config!.userId`. `config` is not part of the saved state. Only the online sign-in sets it (`configLoaded` → `setConfig`). A saved login first signs in offline from storage, and the online sign-in can take up to the 15–20 s request timeouts. Opening grades, the grade chart or the calculator in that window throws `Null check operator used on a null value`. `routingActions.showGrades()` is not awaited by the UI, so the error becomes uncaught (C1 / `E02_asyncFatal` since 1.17.3).
Reproduced on `main` with a store that is signed in without `config`: both loads throw at `grades.dart:74` and `grades.dart:141`, the same frames as C3/C4.

### G3 – Grade chart with a zero-width plot area (C5) – `confirmed (static)`

`LinearScaleFunction` computes `scalingFactor = rangeDiff / domainDiff`. With a 0 px range (chart laid out offstage or during rotation; the sample is landscape and inside `RenderOffstage`), the factor is 0. `reverse()` then divides by 0, and `DateTimeScale.reverse` calls `.round()` on NaN/Infinity. The chart code is unchanged since 1.16.0, so the crash is still possible.

### G4 – Chart drag that ends without an update (C6) – `confirmed (static)`

`ChartGestureDetector.onScaleEnd` reads `_lastScale!`. Only `onScaleUpdate` sets that field, so a pan/scale that starts and ends without an update event crashes. The vendored code is unchanged.

### G5 – Calendar provider without an `isPrimary` column name (C7) – `confirmed (static)`

`MainActivity.listWritableCalendars` looks up columns by name. On some providers (Xiaomi, Android 9 in the sample) the `IS_PRIMARY` projection comes back named `COALESCE(isPrimary, ownerAccount = account_name)`, so `getColumnIndexOrThrow("isPrimary")` throws and calendar sync cannot list calendars. The code is unchanged.

### G6 – Already fixed, waiting for users to update (C8–C14) – `outdated / already fixed`

| Finding | Fixed by | First version with the fix |
| --- | --- | --- |
| C8 notification tap NPE | `2c5650be` (#129) | after 2.0.0+56 (not yet released) |
| C9 profile `email!` | `8ff9b6fd` | 1.17.0 |
| C10 missing chart subject theme | `56b1a6b4` | 1.17.0 |
| C11 uncaught error from session refresh | `4373b1f8`, `4512331c` (`_refreshSession` catches and reports) | 1.17.0 |
| C12 login page instead of config during session refresh | `4373b1f8` | 1.17.0 |
| C13 calendar row removed during refresh | `e1fb6763` | 1.17.4+54 |
| C14 omitted attachment opener (AUD-037, #71) | `67c31543` | 1.17.4+54 |

All C9–C14 events in the window come from 1.9–1.16 installs.

### G7 – Not app crashes (C2, C15, C16) – `documented`

- C2/C16: `E08_login` non-fatals are failed sign-in requests (`api_endpoint=/auth/login`, `http_status=0`, `request_timeout=true`). The network interceptor deliberately reports timeouts and connection errors. Events cluster at the same minutes across many users, which points to school server latency rather than a client defect. No code change. Once G1 is fixed, these group by real frames, which makes the remaining login failures visible.
- C15: the "other school" address field defaults to `.digitalesregister.it`, which `fixupUrl` accepts. Since 1.17 the sign-in catches the host-lookup failure, so it is no longer a crash. It still shows a connection error instead of "enter your school address". That is a UX defect, outside this crash issue.

### G8 – Too little data (C17, A1) – `needs more data`

- C17: one event of a Hero assertion on 1.17.4 with no screen context. Revisit once G1 ships.
- A1: two background ANRs where Crashlytics found no root cause (main thread idle in `nativePollOnce`). The custom keys show a completed timetable save just before; there is no app frame to act on.

## Load time

- Data: no Performance Monitoring. Breadcrumbs of older builds log `app_first_frame` at 102, 119, 191, 210, 248, 322, 330, 402 and 561 ms after `main()` (9 samples, median 248 ms). `theme_loaded` is 0 ms, and `notification_service_initialized` is 67–495 ms (after the first frame).
- Code: `main()` awaits only analytics/privacy init, the app clock, language/theme/settings preferences, a legacy-data cleanup and the widget launch handler before `runApp`. Everything else runs after the first frame. Offline-first sign-in shows saved data before the network request.
- The slow cases in the field are network timeouts of the school server (sign-in requests failing after 17–28 s). The client bounds them at 15 s connect / 15 s send / 20 s receive.
- Result: no measured client-side load-time defect. The remaining waits are server timeouts. Changes are not justified without profiling data. Recommended to get data: add Performance Monitoring or a startup trace, or give the tools access to Play vitals.

## Memory

- Data: no low-memory kill or OOM signal is available (Crashlytics does not record them; Play vitals not reachable). Device memory in the events is system-wide, not per app.
- Static scan of `lib/`: every `TextEditingController`, `ScrollController`, `AnimationController`, `FocusNode`, `Timer`, stream subscription and listener created in a widget or service is disposed or cancelled, or belongs to an object that is. The diagnostics queues are bounded (`_reported` keeps 32 entries; the `_tail` chain releases completed futures).
- Result: no confirmed leak. Status `needs more data`. A heap comparison over repeated navigation needs a device or emulator, which this environment does not have.

## Fix plan (impact × effort)

| # | Fix | Findings | Impact | Effort |
| --- | --- | --- | --- | --- |
| 1 | Keep release-mode stack frames in diagnostics | G1 (C1, C2, C16, C17) | Makes 609 fatal events/404 users per month diagnosable; splits C1 by cause | small |
| 2 | Wait for the online sign-in before loading grades; never dereference a missing `config` | G2 (C3, C4, part of C1) | Removes a reproduced crash on the most used screen | small |
| 3 | Guard the zero-width chart scale | G3 (C5) | 14 users | small |
| 4 | Guard `onScaleEnd` without an update | G4 (C6) | 2 users | small |
| 5 | Read calendar columns by projection position | G5 (C7) | Calendar sync on affected Android providers | small |
| – | Document G6–G8, load time and memory | – | – | – |

## Final status

Filled in after the fixes.
