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
| P3 | first frame → first meaningful screen (login page, or dashboard with saved data) | `p3_saved_accounts_read`, `p3_offline_sign_in`, `p3_launch_gate_open`, `p3_launch_target_ready`, `p3_launch_overlay_removed` |
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
| Slow-server simulation, gate open at 500 ms / 3 s / 20 s per request | 1612 / 9111 / 60114 ms | see final table |
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
