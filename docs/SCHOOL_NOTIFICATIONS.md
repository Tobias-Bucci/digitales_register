# Personal school notifications — Issue #82

## Implemented behavior

The app reuses the bell's `api/notification/unread` feed. Personal `grade` and
`message` entries produce native notifications; other notification types remain
in the bell. This is separate from server-managed general announcements (#78).

Settings include independent grade and school-message switches, enabled by
default. Permission is requested only from the explanatory settings button.
German, Italian, English and Ladin strings are included. Notification titles and
bodies are generic: grades, subjects, sender names and message contents are never
copied into system notifications. Android uses separate grade/message channels
and private lock-screen visibility. Desktop platforms use native notifications
while the app is running; Windows/Linux require explicit app consent and their
notification daemons enforce system policy.

Login, resume and bell refresh reuse the existing Redux middleware and request
coalescing/cache. While the app is active, a three-minute timer requests a feed
refresh when notification preferences and permission allow it. Pausing stops
that timer. Read/delete actions persist suppression before the server request,
including offline reads. Opening grades consumes the currently known grade
events, and viewing subject details records their stable grade IDs, including
cached offline details. Opening/reading messages preserves the existing message
read behavior.

## Persistence and duplicate prevention

`SchoolNotificationEngine` identifies events by category and underlying object
ID, with feed-ID aliases. When neither ID exists, it conservatively groups events
by category and sent timestamp; changing display text or ordering does not change
identity. A feed ID gaining object context is linked to its original history.
Malformed entries are ignored. Unknown types are not guessed to be grades.

Each school URL/account has its own SHA-256 identity. URL host casing and trailing
slashes are normalized, while case-sensitive URL paths and usernames remain
distinct. No password, token or server URL is placed in a notification payload.
Payloads contain a version, opaque account hash, category and optional object ID.

History is stored in an AES-encrypted lazy Hive box in application support, with
the random encryption key in the existing secure-storage platform. Account
records contain hashes and baseline timestamps, without notification contents.
Lazy access loads only the requested account. Normal updates retain this store;
claims are not evicted, so removed and later reappearing events do not replay.
Unchanged checks do not rewrite the history. Corrupt/unreadable history fails
closed rather than silently clearing deduplication state.

The first successful sync establishes both category baselines without alerting.
Enabling a category or newly granting permission establishes a fresh baseline.
Events found while disabled, denied, already read or older than the baseline are
consumed silently. The API's sent timestamp is assumed to be a publication time
using the school's existing timestamp convention.

An in-process mutex and, on mobile, a SQLite exclusive transaction serialize
foreground and background engines. SQLite stores only a mutex counter; encrypted
Hive contains the history. Contention yields/retries in Dart instead of blocking
sqflite's shared native thread. Hive is reopened while holding the lock so a
different engine's committed claims are visible. Workers close native database
connections before exiting; killed workers release the SQLite transaction.

**Delivery is deliberately at most once.** Claims are flushed before calling the
native notification API. A crash/native error between claiming and presenting
can lose an alert, but a retry cannot repeat an alert already delivered. Exactly
once presentation across an app database and an OS notification API cannot be
made atomic. Account changes/logouts clear delivered alerts and disable the old
active account while retaining its isolated deduplication history.

## Background execution

### Android

WorkManager schedules one unique network-constrained periodic job with a
15-minute minimum interval hint and exponential retry backoff. Its native
implementation persists jobs through normal process termination/reboot. Startup
no longer cancels all JobScheduler work or clears all notifications. Android 13+
notification permission and a retained monochrome notification icon are configured.
Doze, battery restrictions, OEM policies and force-stop can delay or prevent work.

The existing AGP 9/built-in-Kotlin Android worker fork is reused. Its matching
`workmanager_platform_interface` (0.9.1+1) and Apple implementation (0.9.1+2)
are pinned: newer interface releases change Pigeon wire tags and must not be
upgraded independently of this native fork.

### iOS

The app registers `it.bucci.digitalesregister.schoolRefresh` with BGTaskScheduler
before launch finishes, enables the `fetch` background mode, advertises the task
identifier and registers plugins for the background Flutter engine. The native
notification center forwards interactions through FlutterAppDelegate. Scheduling
uses BGAppRefreshTask with a 15-minute earliest-run hint. Settings also check
`UIApplication.backgroundRefreshStatus` and explain when refresh is unavailable.

**iOS decides whether and when to run a task.** Fifteen minutes is not a delivery
guarantee. Runs may be infrequent or absent, especially after force-quitting,
disabling Background App Refresh or under power restrictions. The app always
retains foreground synchronization as a fallback.

### Authentication, heartbeat and retries

The worker reads the existing saved-login record; it does not duplicate
credentials into task arguments or retain cookies on disk. It requires HTTPS,
disables redirects and has request timeouts plus a 20-second network cancellation
deadline. An active account must match the saved login. Password-saving-disabled,
demo/debug, signed-out and mismatched accounts are skipped. Authentication
rejections, expired credentials and two-factor challenges are left for the
foreground app; no background UI or retrying authentication loop is opened.

On iOS, enabled background sign-in updates the existing saved-login record to
device-only Keychain accessibility after first unlock. Before the first unlock
after reboot, secure data may be unavailable and the OS must grant a later run.

A foreground heartbeat is refreshed every three minutes and expires after six.
Pause removes it. The worker skips active foreground sessions and checks completed
within the previous two minutes, avoiding competing school sessions and redundant
traffic. A stale heartbeat after a crash cannot suppress delivery indefinitely.
Network/storage failures leave claims intact and return failure for OS-controlled
retry; native presentation failures also retain claims to prevent duplicates.

## Navigation

Cold-start launch details are queued until login and the scaffold are ready,
with a post-frame retry. Running/background taps use the same handler. The active
account is validated before routing, and covering modal routes are dismissed.
School messages use the existing message-ID expansion; missing/deleted messages
fall back to the message list. Grades open the existing grades page: the app has
no standalone grade-ID detail route. The normal biometric lock overlay remains
in effect.

## Backend requirements

There is no personal-event push provider/token registration or notification
backend in this repository. Firebase Analytics/Crashlytics do not provide that
service. The implemented HTTPS polling path requires no new backend, but cannot
observe an event that is read/removed on another device before a successful check.

Near-real-time delivery would require a school-authorized event/webhook or
server-side synchronization service, authenticated per-account subscriptions,
APNs/FCM device-token registration, credential/session and two-factor handling,
token rotation/deletion, and a privacy-reviewed generic push payload. Push
delivery itself would still be subject to OS/network restrictions.

## Verification and release qualification

Automated tests cover quiet baselines; single delivery for grades/messages;
restart persistence; large histories; viewed/disabled/denied suppression;
re-enabling; account isolation; ID/context changes; modified/deleted/reordered
entries; concurrent engines; partial native failures and storage retries;
encrypted storage; background HTTP authentication and coalescing; active,
paused and expired heartbeats; transient SQLite contention; cold/warm tap
callbacks; and settings layouts in all four languages, both themes and large text.

Local verification on 2026-10-23:

- Full Flutter suite: **1,144 passed, 2 skipped**, including 44 notification
  engine/service/settings tests.
- `flutter analyze --no-pub`: **no issues**.
- Android and Windows debug builds: **passed**.
- iOS task identifiers, background mode and plugin callback, Android permission,
  and all four locale catalogs: configuration consistency checks passed.
- Settings previews were rendered and inspected in light/dark themes; large-text
  layouts were also tested.

Final logs are `build/notification_tests_final.log`,
`build/notification_analysis_final.log`, `build/notification_android_final.log`
and `build/notification_windows_final.log`. Generated logs/previews under `build/`
are not source artifacts.

The implementation is ready for review. **Keep Issue #82 open until the following
Apple build and physical-device release qualification have passed.**

Before closing/releasing the issue:

1. On macOS, resolve Apple dependencies and build iOS (`flutter build ios
   --no-codesign`), then test a signed build on an iPhone. This Windows workspace
   cannot compile/link Apple targets.
2. On physical Android/iOS devices, use an authorized school test account to
   confirm real feed types/IDs/publication timestamps and local native delivery,
   denied permissions, channel settings, locked-device behavior, background runs,
   reboot/force-stop/force-quit recovery, account switching and cold-start taps.
3. Qualify signed release builds and packaged desktop activation. Windows/Linux
   notification settings cannot be queried through the selected plugin; the
   system enforces them. Linux cold-start notification activation is outside this
   plugin's support; running-app activation is supported.
4. Review Ladin wording with a native speaker.

No physical-device background delivery, live school-account delivery, iOS build,
or macOS/Linux build is claimed by the local automated verification.
