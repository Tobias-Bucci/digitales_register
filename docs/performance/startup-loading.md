# Startup and load times

Refs #23. This is the load-time follow-up of `docs/stability/issue-23-triage.md`,
which could not measure anything. All numbers below were measured as described
in [Method](#method); anything that could not be measured is marked as such.

## Phase model

| Phase | From → to | Marks (`[startup] …`) |
| --- | --- | --- |
| P0 | process start → `main()` | not visible to Dart; `am start -W` minus P1+P2, and `start_up_info.json` |
| P1 | `main()` → `runApp` (every awaited call) | `p1_binding_ready`, `p1_privacy_analytics` (= `p1_privacy_consent` + `p1_launch_context`), `p1_app_clock`, `p1_language`, `p1_settings`, `p1_language_apply`, `p1_theme`, `p1_legacy_cleanup`, `p1_store_created`, `p1_widget_launch_handler`, `p2_run_app` |
| P2 | `runApp` → first frame | `p2_first_frame` (navigator mounted after the first frame) |
| P3 | first frame → first meaningful screen (login page, or dashboard with saved data) | `p3_saved_accounts_read`, `p3_offline_sign_in` (contains `p3_saved_state_decode`), `p3_launch_gate_open`, `p3_launch_target_ready`, `p3_launch_overlay_removed` |
| P4 | online sign-in (login request + config page) | `p4_online_sign_in` |
| P5 | first network data (dashboard, notifications, profile) | `p5_first_data` |
| P6 | deferred services after the first frame | `p6_after_first_frame_init` (whole start action included), `p6_package_info`, `p6_restore_preferences`, `p6_notifications_init` |

`p3_launch_gate_open` is when the start-up routing lets the launch animation
uncover the app; `p3_launch_target_ready` adds the route transition;
`p3_launch_overlay_removed` is the end of the reveal. The launch animation
itself has a fixed length (`LaunchTimings`: 1.3 s intro + 0.5 s reveal), so
the overlay can never be gone before about 1.8 s after the first frame. Any
work that finishes before the intro ends is hidden by the animation; work that
finishes later makes the check "breathe" (`holdPulse`) until it is done.

## Instrumentation

`lib/startup_timeline.dart` (`StartupTimeline`, global `startupTimeline`):

- `start()` in `main()`, `step(name, body)` for awaited work, `mark(name)` for points.
- Each name is recorded once, only during the first two minutes of the
  process. Later sign-ins (account switch, resume) are not recorded.
- Debug and profile builds print one line per mark (`[startup] <name> at=…ms
  took=…ms`) and emit `dart:developer` timeline events (`startup:<name>`) for
  DevTools/Perfetto. Release builds compile the calls down to running the step
  itself; nothing is recorded, printed or sent.
- Labels are fixed strings. No account names, URLs, grades or other school data
  are passed in, and nothing goes to analytics or Crashlytics.

## Method

Environment: Windows 11 host, Flutter 3.47.7. Commit of the baseline: the
instrumentation commit on top of `dcc4f686`.

1. **Emulator cold starts** (`dr_launch_api35`: Android 15 / API 35, x86_64,
   4 cores, 2.5 GB). Profile APK (`flutter build apk --profile`, application
   ID `it.bucci.digitalesregister.profile`, so it never touches the installed
   app). Each run: `am force-stop`, `logcat -c`, `am start -W`, wait, read the
   `[startup]` lines from logcat. 11 runs per set; the first run is reported
   separately, the table shows the median and min–max of the other 10.
   - *Login page*: no saved login.
   - *Saved login*: the built-in demo account (`demo`/`demo`, no school
     address) signed in with "stay signed in". It runs the real offline-first
     path (saved accounts → offline sign-in → online sign-in → first data), but
     the demo "server" is local, so P4/P5 take no network time.
2. **`flutter run --profile --trace-startup`** on the same emulator, 4 runs
   (`build/start_up_info.json`). Tracing adds overhead; use it for P0 only.
3. **Slow-server simulation**: a scratch test (kept outside the repo) runs the
   real start-up middleware (`actions.start`) with a saved login against a fake
   `HttpClientAdapter` whose every response takes 0 / 500 / 3000 / 20000 ms,
   once answering and once failing with a receive timeout. One process per run,
   3 runs per case. This isolates the effect of blocking vs. non-blocking
   design from the real school server. (The fake adapter does not enforce Dio's
   15/15/20 s timeouts, so the 20 s case shows a server that answers just
   before them.)

Not measurable here:

- **Real phone.** A Galaxy S24+ was connected, but its existing `dr PROFILE`
  install may hold a saved school login; repeated cold starts would sign in to
  a real account. It was not used.
- **Firebase cost.** Firebase is not configured for the profile flavour, so
  P1 on the emulator does not include `Firebase.initializeApp` and the
  Crashlytics/Analytics consent calls that a release build makes there.
  Release builds are not run here (`assembleRelease` uploads to Crashlytics).
- **Real school server latency** (field reports: sign-in requests failing after
  17–28 s, see the triage).
- iOS (needs macOS), Linux desktop (Windows host).
- Emulator raster times are slow regardless of the app (software-assisted
  GPU); frame numbers are only compared before vs. after on the same emulator.

## Baseline

### Emulator, cold start, profile (ms after `main()`, median [min–max] of 10)

| Phase / mark | Login page | Saved login (demo) | Blocking? | Needed for first meaningful screen? |
| --- | --- | --- | --- | --- |
| `am start -W` TotalTime (process start → first frame on screen) | 1286 [1231–1357] | 1386 [1278–1522] | – | – |
| P0 engine enter → framework init (`--trace-startup`, 4 runs) | 250 [233–274] | – | yes | yes |
| P1 `p1_privacy_analytics` | 404 [10–419] took | 438 [409–467] took | yes (awaited before `runApp`) | consent gate yes; launch context no |
| P1 other awaited steps (clock, language, settings, theme, legacy cleanup, widget handler) | < 6 together | < 6 together | yes | language/theme/settings yes; cleanup no |
| P2 `p2_run_app` → `p2_first_frame` | 412 → 433 | – → 466 | yes | yes |
| P3 `p3_saved_accounts_read` | 500 (33 took) | 600 (98 took) | after first frame | yes |
| P3 `p3_offline_sign_in` (saved data mounted) | – | 654 (61 took) | after first frame | yes |
| P4 `p4_online_sign_in` | – | 694 (31 took, local demo) | **blocks the launch gate** | no |
| P5 `p5_first_data` | – | 710 (12 took, local demo) | **blocks the launch gate** | no |
| P3 `p3_launch_gate_open` | 502 [482–549] | 710 [645–747] | – | – |
| P3 `p3_launch_target_ready` | 741 [728–761] | 726 [660–760] | – | – |
| P3 `p3_launch_overlay_removed` (app usable) | 2266 [2247–2285] | 2294 [2266–2319] | – | – |
| P6 `p6_notifications_init` | took 246 | took 283 | no (after first frame) | no |
| Launch frames: total / slow build (>16.7 ms) / worst build | 104 / 0 / 7.6 ms | 160 / 0 / 12.8 ms | – | – |

First (discarded) runs were within the min–max above except P1 on the saved
login run (421 ms took).

Findings:

- **P1 is ~400 ms and almost all of it is one wait.** The other awaited steps
  take < 6 ms together. Across runs the wait moves between
  `p1_privacy_consent` and `p1_launch_context` (e.g. 380/3 ms in one run,
  6/384 ms in the next): it is the first platform-channel call that needs the
  Android main thread while that thread is still creating the activity, not
  work of either step.
- **The overlay can only go away 1.3 s + 0.5 s after the first frame**
  (`LaunchTimings`). With the login page, or a saved login whose server
  answers in time, everything in P3 finishes inside the intro and is hidden by
  the animation.
- **With a saved login the launch gate waits for the network.** `_loadAccounts`
  awaits the whole `login` action, which awaits the online sign-in (login
  request + config page) and then `loggedIn`, which awaits the first data
  loads. Saved data is mounted at ~50 ms, but the app stays covered:

### Slow-server simulation (ms after the start action, median of 3 runs)

| Server latency per request | Saved data mounted (`p3_offline_sign_in`) | Online sign-in done (`p4`) | First data (`p5`) | **Launch gate open** |
| --- | --- | --- | --- | --- |
| 0 ms | 45 | 82 | 101 | **102** |
| 500 ms | 48 | 1090 | 1611 | **1612** |
| 3 s | 49 | 6088 | 9109 | **9111** |
| 20 s | 52 | 40092 | 60112 | **60114** |
| 0 ms, request fails | 48 | 73 | – | **76** |
| 500 ms, request fails | 55 | 579 | – | **583** |
| 3 s, request fails | 44 | 3066 | – | **3070** |
| 20 s, request fails | 50 | 20073 | – | **20077** |

The gate opens after ≈ 3 × latency (login, config, first data) when the server
answers, and after the failed request when it does not. During that time the
launch animation "breathes" over a dashboard that already shows the saved data.

## Changes

### 1. Uncover saved data before the online sign-in (P3/P4)

`_login` opens `appLaunchGate` right after the offline sign-in from storage
has mounted the saved data, instead of `_loadAccounts` opening it after the
whole `login` action (online sign-in + config + first data loads). The online
sign-in and the first loads keep running exactly as before; the dashboard shows
their progress with its existing loading indicator. Nothing else waits on the
gate except the launch animation; the first-run dialogs in `_loadAccounts`
still come after the sign-in as before.

Behaviour that changes on purpose: with a saved login the user sees the saved
dashboard while the sign-in runs. If the server then rejects the password
(changed elsewhere) or needs a new 2FA code, the login page or 2FA dialog
replaces the dashboard afterwards, as it already did for account switches.
Before, a 2FA dialog during a cold start was pushed while the launch overlay
still covered the app.

| Measurement | Before | After |
| --- | --- | --- |
| Slow-server simulation, gate open at 500 ms / 3 s / 20 s per request | 1612 / 9111 / 60114 ms | see [final table](#final-before--after) |
| Emulator, demo login with a simulated 3 s sign-in, `p3_launch_overlay_removed` (median of 11, 2 alternating batches) | 4743 [4588–4917] | 2448 [2397–2487] |
| same, `p5_first_data` (data refreshed) | 3850 | 3842 |
| same, launch frames: slow build median / worst build | 1 / 17.5 ms | 0 / 15.9 ms |
| Emulator, demo login without delay, `p3_launch_gate_open` (median of 10) | 710 | 658 |
| same, `p3_launch_overlay_removed` | 2294 | 2317 (animation-bound, within noise) |
| same, alternating batches (11 each): slow build median / worst build | 0 / 14.8 ms | 0 / 15.5 ms |

The simulated sign-in delay was a temporary scratch patch in the demo branch of
`Wrapper.login` (`Future.delayed`), built with
`--dart-define=DR_SIM_SIGN_IN_MS=3000` for both APKs and never committed.

Tests: `test/startup_offline_first_test.dart` (saved data uncovered while the
server holds the sign-in; offline after a timeout; login page without a saved
login). The first two fail without the change.

### 2. Skip the legacy cleanup round trips (P1)

`removeLegacyNotificationData` ran five awaited `prefs.remove` calls before
`runApp` on every start, although the keys are long gone on almost every
device. It now removes only keys that exist (`containsKey` reads the cache
that `SharedPreferences.getInstance` already loaded).

| Measurement (emulator, demo login, alternating batches, median of 11) | Before | After |
| --- | --- | --- |
| `p1_legacy_cleanup` took | 3.2 [2.6–5.6] ms | 0.0 ms |
| `p2_first_frame` | 609 ms | 613 ms (within noise: the main-thread wait dominates) |

Kept because it provably removes five platform round trips from the critical
path; it does not change the first frame measurably on its own.

### Tried and reverted: launch context after the first frame (P1)

Moving `p1_launch_context` (package info, install source, version write for
the diagnostics context) behind the first frame did not bring `runApp`
forward: the main-thread wait moved to the next platform call before
`runApp`, `p1_language_apply` (a preferences write), in 3 of 12 runs, and
stayed in `p1_privacy_consent` in the others (alternating
batches, `p2_run_app` median 1344 → 1308 ms on a slowed-down emulator, within
noise). The P1 wait is the Android main thread finishing the activity, which
the first frame needs anyway; reordering Dart awaits cannot remove it, and the
consent step must stay before `runApp`. Reverted, not committed.

### Measured, left alone: saved-state decode (P3)

`p3_saved_state_decode` (JSON decode + `built_value` deserialize of the saved
state, synchronous on the UI isolate during the launch intro) takes 1.6 ms
[1.3–2.7] for the demo account (~60 KB saved state; emulator, median of 10).
Moving it to an isolate would cost more than it saves at this size. The step
stays instrumented so it can be measured on a real account with a full school
year.

## Final before / after

Baseline = commit `bc92d391` (instrumentation only), final = `9232f5a2`.
Emulator rows: profile APKs of both commits, cold starts in interleaved
batches on a freshly booted emulator (saved login: 2 rounds of 6 each;
login page: 4 rounds of 6 each, order reversed in rounds 3–4), first run of
each set reported apart, median [min–max] of the rest.

| Phase / metric | Method | Before | After |
| --- | --- | --- | --- |
| P0 engine enter → framework init | `--trace-startup`, 4 runs | 250 [233–274] ms | not changed (no code on this path) |
| P1 `p1_legacy_cleanup` | emulator, login page, n=23 | 3.1 [1.5–6.1] ms | 0.0 ms |
| P1 total (`p2_run_app`) / P2 `p2_first_frame` | emulator, login page, n=23 | first frame 446 [406–594] | 448 [433–5228¹] |
| P3 gate open, login page | emulator, n=23 | 585 [474–698] | 539 [501–5295¹] (within noise; no change on this path) |
| P3 overlay removed, login page | emulator, n=23 | 2283 [2233–2481] | 2284 [2259–7061¹] |
| P3 gate open, saved login (demo, local) | emulator, n=11 | 629 [553–679] | 584 [543–607] |
| P3 overlay removed, saved login (demo, local) | emulator, n=11 | 2241 [2226–2263] | 2242 [2228–2262] |
| P3 overlay removed, saved login, 3 s sign-in (simulated) | emulator, n=11 | 4743 [4588–4917] | 2448 [2397–2487] |
| P4/P5 sign-in + first data done, same | emulator, n=11 | 3850 | 3842 (unchanged, now in the background) |
| P3 gate open, slow server 0 / 0.5 / 3 / 20 s | simulation, n=3 | 102 / 1612 / 9111 / 60114 ms | 50 / 51 / 51 / 47 ms |
| P3 gate open, failing server 0 / 0.5 / 3 / 20 s | simulation, n=3 | 76 / 583 / 3070 / 20077 ms | 49 / 51 / 50 / 47 ms |
| P4 online sign-in done, 3 s server | simulation, n=3 | 6088 ms | 6085 ms (unchanged) |
| Launch frames, slow build (>16.7 ms) median / worst build | emulator, login page, n=23 | 0 / 6.2 ms | 0 / 6.7 ms |
| same, saved login (demo) | emulator, n=11 | 0 / 16.0 ms | 0 / 15.7 ms |
| same, saved login, 3 s sign-in | emulator, n=11 | 1 / 17.5 ms | 0 / 15.9 ms |
| P6 `p6_notifications_init` | emulator, login page, n=11 | 271 ms | 291 ms (not changed; after the first frame) |

¹ One run of the reversed round hit a 5 s emulator stall in `p1_privacy_consent`
before `runApp`; it is kept in the range but does not move the median.

Unmeasured: real phones, Firebase initialization in release (not configured
for profile), real school-server latency, iOS, Linux.

## Animations

Animations that play at start-up and on the first screens, and how they were
checked:

| Animation | Changed? | Check |
| --- | --- | --- |
| Launch overlay: intro (rest, retract/stretch, redraw with spring, light sweep, ring nudges, 1.3 s), hold pulse while waiting, circular reveal (0.5 s), skipped reveal (0.32 s), reduced-motion fade (0.3 s) | No: same `LaunchTimings`/`LaunchCurves`/painter. Only the moment the target is ready moved earlier, so the hold pulse is needed less often. | Launch frame summary (table above); `test/ui/launch_animation_test.dart` (choreography, skip, reduced motion, native splash colours) green. |
| Native splash → first Flutter frame hand-over | No | Same first frame; `am start -W` within noise. |
| Route transition login ↔ dashboard, `_popAll` | No | `p3_launch_target_ready` still waits for the transition (`waitForRouteTransition`). |
| `SplashScreen` fade (250 ms, zero under the launch overlay) | No | – |
| Login page motion (`auth_layout`, `login_page_content`) | No | `test/ui/auth_motion_test.dart` green. |
| Dashboard/grades loading indicators (`AnimatedLinearProgressIndicator`, banners) | No | Now visible while the online sign-in runs on a saved login, as during any refresh. |
| Grade chart animations, Hero on the grades chart | No | Not on the start-up path; grades/chart tests green. |

With the gate change, the online sign-in and first data loads may finish
after the reveal instead of under the hold loop. Their work is the same
network-bound async work as before (no new synchronous work); the frame summary
with the 3 s sign-in shows no slow build frame.

## Not changed, and why

- **Privacy consent before `runApp`.** It decides whether diagnostics and
  analytics may run (and in release initializes Firebase). It stays the first
  awaited step so no telemetry can start before the decision. It is also where
  the main-thread wait usually lands; moving other steps did not help (see the
  reverted experiment).
- **Timeouts (15 s connect / 15 s send / 20 s receive).** Field data shows slow
  but working school servers (17–28 s). Shorter timeouts would turn those into
  failures. With the gate change a slow server no longer blocks the screen,
  and the dashboard shows the loading indicator while it waits.
- **Sign-in request chain.** Login → config page → first data are dependent
  (session cookie, then student id); the first data loads (dashboard,
  notifications, profile) already run in parallel.
- **Notification service, package info, user preferences, deep links, server
  notifications.** Already after the first frame (P6); they run during the
  launch intro without slow build frames.
- **Widget launch handler.** Synchronous handler registration, < 0.5 ms.
- **First-run dialogs** (unmaintained notice, privacy consent) still appear
  after the sign-in, as before; showing them earlier would change when the
  consent question is asked.
- **Lifecycle observer** is still registered after the start action (after the
  online sign-in), as before.

## Remaining bottlenecks and follow-ups

- **School server latency** (P4/P5) is server-side. The app now shows saved
  data during it; the time until fresh data arrives is unchanged.
- **P1 main-thread wait** (~400 ms on the emulator): Android activity creation.
  Needs device profiling (Android Studio system trace / Perfetto of a release
  build) to see what the main thread is doing; plugin registration and
  Firebase are the candidates.
- **Saved-state decode on large accounts:** measure `p3_saved_state_decode`
  on a device with a full school year before deciding on an isolate.
- **Field data:** add Firebase Performance Monitoring (app-start trace plus
  custom traces for the P3/P4/P5 marks), or give the tools Play vitals access.
  Not added here (new dependency).

## How to measure on a device

Profile build (`flutter build apk --profile`) installs as `dr PROFILE` next to
the real app. Cold start: `adb shell am force-stop it.bucci.digitalesregister.profile`,
then `adb shell am start -W -n it.bucci.digitalesregister.profile/it.bucci.digitalesregister.MainActivity`,
then `adb logcat -d | grep "\[startup\]"`. Cases worth running:

1. Saved login, normal network: overlay should go away about 1.8 s after
   `p2_first_frame`, with `p4_online_sign_in`/`p5_first_data` later or earlier
   depending on the server.
2. Saved login, airplane mode: saved dashboard after the intro; offline notice;
   no long hold.
3. Saved login, slow network (Android developer options or a throttling proxy):
   saved dashboard after the intro, loading indicator until `p5_first_data`.
4. No saved login: login page after the intro (unchanged).
5. Opening grades right after the reveal on a slow network: saved grades with
   the linear indicator, no full-screen spinner.

## Verification

| Check | Baseline (`dcc4f686`) | Final |
| --- | --- | --- |
| `flutter analyze` | no issues | no issues |
| `flutter test` | 3377 passed, 1 skipped, 0 failed | 3387 passed, 1 skipped, 0 failed (10 new tests) |
| `flutter build apk --debug` | – | built |
| `flutter build apk --profile` | built | built (also with the scratch sign-in delay, not committed) |

Not run: release builds (`assembleRelease` uploads to Crashlytics), iOS (no
macOS), Linux desktop, a real phone.
