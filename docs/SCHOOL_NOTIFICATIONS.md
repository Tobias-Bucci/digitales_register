# Personal school notifications — Issue #82

Implementation after the 2026-10-24/25 revision. The German completion report is in
`ISSUE_82_COMPLETION_REPORT.md`; device qualification is in
`SCHOOL_NOTIFICATIONS_DEVICE_TESTS.md`.

## Scope and data flow

Personal grades and school messages are detected on the device using the existing
school's `api/notification/unread` feed. This is separate from general app
announcements (#78). No custom backend, APNs/FCM subscription, school webhook or
new school endpoint is introduced. Firebase Analytics/Crashlytics do not run
inside this synchronization path.

```text
UI feed refresh -------------------------+
                                         v
WorkManager / BGAppRefresh -> saved login -> school HTTPS API
                                         |
                                         v
                            shared ingestion + event engine
                                         |
                          encrypted account-scoped history
                              /                     \
                  foreground: quiet           background: grouped
                  existing feed/badge         local system request
```

`school_api_endpoints.dart` shares the existing `/v2/` base, login and unread-feed
contract with `Wrapper` and middleware. The headless Dio client does not
instantiate the UI-aware `Wrapper`: it uses the same endpoints while avoiding
Redux, visible routes, dialogs, indefinite session refresh and analytics.

## Accounts, credentials and settings

### Account opt-in (2026-10-25)

Personal notifications default to **off** until the account has an explicit
decision. Both categories are checked only in the explanatory dialog; this is
not consent. The mounted home route offers it after successful sign-in and the
existing startup notices. It waits for other modals, the foreground and the app
lock; the tutorial follows afterwards. Account changes dismiss the old offer,
and an account/session check rejects stale decisions.

The account preference record contains `decision: unknown | accepted | declined`.
Acceptance saves the chosen categories and quiet baselines before requesting OS
authorization if needed. Declining persists an off state and never opens native
permission UI. Existing stored account choices and earlier global choices for
accounts saved before startup are preserved; a later new account is not opted in
by another account's positive choice. Observed OS permission, event history and
default category flags do not establish consent. Existing global disabling is
never automatically reversed. Settings can change the decision at any time.

A device-wide request marker is persisted before entering native permission UI.
Known iOS denial and Android rationale/restriction states are respected. Android
may not distinguish a never-asked permission from an old permanently denied
permission using public rationale APIs; in that case Android itself refuses the
request without showing another dialog, and the app records the attempt. Future
accounts/toggles cannot repeat that system request. A voluntary settings link
handles permission changes. There is no OS permission prompt on explanatory
dialog display or on declining.

Opt-in tests are `test/school_notification_opt_in_test.dart`,
`test/ui/school_notification_opt_in_test.dart` and the additional engine consent
gate regression. Logs use the `build/issue82_optin_*.log` prefix. Native iOS
permission-status handling still needs Xcode/device qualification.

- The existing secure `login` record remains the only stored school credential
  record. Primary account and `otherAccounts` are read locally. Work payloads
  contain no credentials; cookies live only in the request's memory.
- Previously activated accounts are enrolled by opaque account hash. Finding a
  saved account does not automatically enroll an unvisited one. The previous
  single-account installation migrates without discarding history.
- Preferences are scoped to normalized school URL and case-sensitive username.
  Host casing and trailing slashes normalize. Old global grade/message choices
  remain migration defaults, not reset values.
- Each account has a master switch, grade/message switches, and optional event
  count. Values, subjects, senders and message text remain hidden in every mode.
  Event counts are hidden by default. Account/school labels appear only in
  settings, with the configured accounts' on/off state.
- Global notification permission and the existing password-saving setting gate
  all background checks. Explicit logout revokes the active session/enrollment;
  account switching preserves enrolled accounts. Removal deletes that account's
  history, preferences, diagnostics, throttle and lease and rejects late results.
- iOS uses device-only Keychain accessibility after first unlock for enabled
  background credentials/key material. Before first unlock a run may fail; the
  OS must grant a later run. Locked-device access needs device verification.

Settings distinguish permission, actual pending work, known power/background
restrictions, disabled channels, and four times: last background start, last
background success, last detection, last system notification request. The
system-settings button never changes permissions or battery policy automatically.

## Event identities, persistence and states

The engine accepts `grade` and `message`; unknown announcement types stay in the
in-app feed. A malformed relevant entry fails ingestion before advancing
baselines. A partial invalid feed cannot become a successful empty baseline.

Identity prefers `(category, objectId)` with feed ID aliases. Without object ID,
feed ID is used; without either ID, category plus sent timestamp is the
conservative fallback. Changed ordering, titles or formatting do not create a new
event. Editing a stable object does not trigger another alert: this feed does not
establish reliable version/change semantics.

The account namespace plus event identity covers school, account, type and
server object. Fallback events sharing category/timestamp can be conflated;
without stable IDs lossless identification cannot be guaranteed.

History lives in an AES-encrypted lazy Hive box with its random key in secure
storage. An exclusive SQLite transaction serializes distinct Flutter engines;
an in-process mutex serializes instances inside an isolate. SQLite contains no
school data. Hive reopens under the lock to observe other engines' writes. Busy
locks yield in Dart for up to 20 seconds; network calls never hold this lock.

Known hashes are retained without time-based eviction. New observations store
only server-reported sent time, first detection, storage time and a presentation
decision: initial baseline, server-reported read, disabled, foreground,
permission denied, older than baseline, or claimed. `timeSent` is **not proof of
the underlying grade's creation time**. Legacy history does not gain invented
detection timestamps.

Viewing/acknowledging an event locally records `locallyViewedAt` separately.
Removing a system notification does not set this field or call a school read API.
Opening the grades overview no longer marks every known grade as viewed;
subject-detail and explicit message/read actions retain their own semantics.
These timestamps do not prove a person cognitively read an item.

The first successful feed establishes a quiet baseline. Re-enabling a category,
enabling the master switch or newly granting permission makes the next applicable
baseline quiet; permission restoration covers all enrolled accounts. Disabled,
denied, old and known events never replay as new alerts.

## Foreground/background behavior

Foreground ingestion is always quiet, including startup, resume and refresh
after a long absence. It stores known identities and updates the in-app feed and
badge. It creates no delayed notification queue and does not mark the feed read.

A foreground heartbeat is published before native notification initialization,
renewed every three minutes, and expires after six. Pause removes it. A worker
skips foreground sessions and feeds checked within the last two minutes. A crash
heartbeat cannot suppress checks indefinitely.

Background ingestion requests at most one alert per category/account/batch.
Stable account/category IDs replace previous category alerts. Optional counts
describe the new batch, not the total unread inbox. A single event keeps its
object destination; a batch opens the category list. Android uses normal
importance grade/message channels and account groups; iOS uses account threads.
No critical/time-sensitive bypass is requested.

Startup/resume clears only personal school alerts using channels, validated
payloads or exact account-thread format. General app notifications are retained.
Only submitted personal notification IDs are additionally remembered for scoped
cleanup where desktop enumeration does not expose payloads. Windows cancellation
requires a packaged app identity; Linux cannot recover another process's daemon
notification mappings. These desktop limits do not apply to the mobile channels.
Android additionally clears them in native `onResume` before Dart startup.
`SchoolLocalNotificationsPlugin` subclasses the existing plugin and gates only
personal `show` calls on the native main queue when the process is foreground.
It is installed in UI and headless engines. Other plugin behavior is delegated.
iOS native `willPresent` suppresses personal foreground alerts/sounds; background
requests retain normal notification sound behavior.

## Background execution, authentication and retries

Android registers one unique network-constrained periodic WorkManager job:
`it.bucci.digitalesregister.schoolRefresh`. Interval/initial delay: 15 minutes;
policy: keep; exponential retry backoff starts at one minute. WorkManager persists
work through ordinary process death/reboot. Doze, restrictions, OEM policies,
force-stop and networking can delay/prevent execution.

iOS registers the identifier before launch returns, declares `fetch` and the
permitted identifier, and registers plugins/lifecycle handling in the headless
engine. BGAppRefresh receives a 15-minute earliest-run hint. The local Apple fork
preserves pending requests, reports scheduling failures, cancels the engine on
expiration, and unblocks the operation semaphore. Missing callbacks and Dart
failures complete as failure. These Swift changes have not been compiled here.
Disabling notifications cancels pending work even when Background App Refresh is
currently unavailable; the availability warning cannot bypass cancellation.

The OS chooses whether/when iOS refresh runs. Force-quitting, disabled refresh
and power restrictions may prevent it. Neither platform guarantees 15-minute
polling or immediate notifications.

Eligible saved accounts run sequentially, least recently attempted first, within
a shared 20-second network budget. Each phase has 8-second connect/send/receive
limits. One login and one unread-feed request are needed per checked account;
with both categories disabled there is no request. No documented category-filter
or incremental cursor exists in the reused contract, so none is invented.

A persisted 45-second per-account lease prevents two engines authenticating the
same account simultaneously and expires after a killed worker. Repeated calls
share an in-flight Future. Before commit the worker rechecks active session,
enrollment, credential record, permission, heartbeat, preferences and recent
foreground checks. Removed/superseded results are discarded. Fair ordering gives
accounts excluded by a slow school/time budget priority on later runs.

HTTPS is required, redirects are disabled, URL credentials/query/fragment are
rejected, and demo/debug accounts are skipped. Expired/2FA/401/403 authentication
requires the normal UI and pauses background login until a new app session.
Network/timeouts retry through the scheduler without an authentication loop.
Diagnostics store fixed error categories, never exception bodies or request data.

## Delivery semantics and navigation

Claims are flushed **before** OS submission. This favors at-most-once submission:
a crash between claim and request may lose an alert; retry cannot replay an
already claimed event. There is no atomic transaction between Hive and the OS
notification center and no exactly-once display guarantee.
`lastNotificationRequestedAt` records an attempted submission;
`lastNotificationAcceptedAt` means the native call returned. Neither proves
display/delivery. Permission, channels, DND or the foreground gate may suppress it.

Cold/warm taps carry only version, opaque account hash, category and optional
object ID. Normal sign-in and the biometric lock remain authoritative. Different
saved accounts resolve through the existing selection/sign-in flow; absent
accounts receive a localized explanation. The destination survives the
notification's first account switch; a later manual switch/logout supersedes it.
Messages use existing ID expansion/list fallback. Grades open the grades view:
there is no standalone grade-ID route. End-to-end cold-start/2FA/account routing
still requires physical-device qualification.

## Limits and verification

An unread-only feed cannot reveal an event read/removed on another device before
polling. Inconsistent school IDs, timestamps and unsupported authentication need
authorized real-school verification. This synchronization path sends no school
credentials or personal events to an app-owned backend. Such a backend, without
school events, cannot provide guaranteed real-time detection.

Run focused tests, the full Flutter suite, analyzer, Android build, native worker
tests, and `python tool/check_school_notification_config.py`. The latter checks
configuration consistency only; it is not an iOS build/runtime test. Evidence for
the initial revision is in the completion report; current opt-in behavior and
test results are in `SCHOOL_NOTIFICATIONS_OPT_IN.md`. **Keep Issue #82 open pending Xcode
compilation, signed release and physical Android/iPhone qualification.**

Platform references:

- [Android periodic work](https://developer.android.com/reference/androidx/work/PeriodicWorkRequest)
- [Android Doze/App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)
- [Android background restrictions](https://developer.android.com/topic/performance/background-optimization)
- [Apple background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)
