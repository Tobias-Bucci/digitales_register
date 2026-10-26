# School notifications — end-to-end debugging report (Issue #82)

Date: 2026-10-26. Base: `main` at `b0ff7e06`. Changes are local and uncommitted.
Environment: Windows 11, Flutter toolchain, no Android device/emulator (`adb` not
on PATH), no macOS/Xcode. **Issue #82 must stay open** (see the last section).

## 1. Summary

| Platform | Root cause found | Status |
| --- | --- | --- |
| iOS | **Yes — confirmed in code.** The background worker could never read the saved login, so every BGAppRefresh run skipped every account silently. | Fixed; Dart-level regression tests; Swift/Xcode and device unverified |
| Android | No code-level defect found in the worker path. | One diagnostic added; real delivery still needs a device |

## 2. Root cause (iOS): Keychain accessibility class mismatch

### Evidence

`flutter_secure_storage_darwin` 0.3.2 (`FlutterSecureStorage.swift`) puts
`kSecAttrAccessible` into **every** Keychain query (`baseQuery`) when an
accessibility option is set. That includes `read`, the existence check inside
`write` (`containsKey`) and the `SecItemAdd` fallback. Only `delete` drops the class.
On the Dart side `AppleOptions.accessibility` defaults to `unlocked`.

Before this fix:

- The UI stored `login` with `const FlutterSecureStorage()`, so the item was
  `kSecAttrAccessibleWhenUnlocked`.
- `SchoolNotificationService` on mobile used
  `IOSOptions(accessibility: first_unlock_this_device)` for **all** reads,
  including `login`.

Consequences on iOS:

1. `_backgroundSyncAccount` read `login` → query for after-first-unlock items →
   `errSecItemNotFound` → `null` → `return null`. No login, no feed request, no
   notification, no diagnostic (only a debug-mode `background-skipped` trace).
   The job still completed as "success".
2. `_prepareBackgroundCredentials` ("upgrade login to after-first-unlock after
   consent") read `login` the same way, got `null` and wrote nothing. The
   documented upgrade never happened.
3. `reload()` read `login` the same way, so the iOS settings screen listed no
   enrolled accounts.
4. Had the upgrade ever succeeded, the UI's fixed-class read would have lost the
   saved login, and its write would have collided (`errSecDuplicateItem`). Because
   of this, the worker storage alone could not be fixed: the UI storage had to change too.

Android is not affected: both storages use identical Android options.

### Fix

- `lib/desktop.dart`: new `keychainAnyAccessibility` (`IOSOptions(accessibility: null)`);
  `getFlutterSecureStorage()` uses it. Reads match an item of any class; updates
  keep the item's class; new items still get Apple's default (when unlocked), as
  before. Existing items stay readable with no migration. Other platforms ignore iOS options.
- `lib/school_notification_background.dart`: new `SchoolNotificationKeychain`.
  It reads without a class. On iOS it writes after-first-unlock, device-only.
  If the write collides with an item of another class, it deletes the item (a
  class-independent delete) and recreates it after-first-unlock. If recreation
  fails, it writes the value back readable for the UI and rethrows, so the
  saved login is never lost.
- `lib/school_notification_service.dart`: the mobile storage is now
  `const SchoolNotificationKeychain()`. The existing consent-gated
  `_prepareBackgroundCredentials` now actually upgrades `login`.
- A missing or unreadable saved login (or a record without this account's
  password) now records the fixed category `backgroundResult: credentialsUnavailable`
  instead of skipping silently. Demo/debug accounts are still skipped silently.
  New localized text in de/en/it/lld. The Ladin text needs native review, like
  the existing catalog.

The consent, permission, account isolation, encrypted history and claim
semantics are unchanged. No credential is copied into a second record.

## 3. End-to-end trace (expected vs. actual)

| Step | Android | iOS |
| --- | --- | --- |
| Opt-in `unknown/accepted/declined`, master/category switches, permission marker | Matches docs | Matches docs |
| Password-saving gate (`school-notification-background`) | Default `noPasswordSaving=false`; hard logout only on explicit logout | Same |
| Scheduler | Unique periodic `it.bucci.digitalesregister.schoolRefresh`, 15 min, network, `update`, no extra delay, exponential backoff 1 min (verified in the `workmanager_android` fork) | BGAppRefresh registered before launch returns; `fetch` + permitted ID; pending request preserved; reschedule on run |
| Headless engine + plugins | Native plugins via `FlutterEngine(context)`; app configurator installs gated plugin and lifecycle channel | Registrant callback registers plugins + `dr/school_notifications` |
| Dart notification plugin | Explicit `registerWith()` (defense in depth; engine registrant also runs) | Same |
| Native visibility gate | `SchoolNotificationVisibility` (started Activities); native `show` gate on `school_*` channels | `applicationState != .background`; `willPresent` suppresses personal alerts |
| Saved login + enrollment | Readable | **Broken → fixed** (section 2) |
| HTTPS login + unread feed | Same request shape as `Wrapper`; HTTPS only, no redirects, isolated cookies, 8 s phase limits | Same |
| Ingestion, identity, baselines, claims | `grade`, `message`, `messageShared`; claims flushed before `show` | Same |
| Notification request | Channel `school_grade`/`school_message`, account group, private visibility; icon kept from resource shrinking (`res/raw/keep.xml`) | Account thread; sound on |
| Tap payload / navigation | Version, account hash, category, optional ID only | Same |

Other paths checked and found consistent with the docs: the UI never fetches
while backgrounded (`Wrapper.send` returns early), so foreground ingestion cannot
quietly consume events meant for a background alert. Lease, session token,
stale-result checks and the two-minute recent-sync skip match the docs.
`flutter_local_notifications` 22.3.2 does not take over the
`UNUserNotificationCenter` delegate in headless engines. Gson in that plugin is
only used for scheduled notifications, which this feature does not use.

## 4. Remaining risks (not changed)

- **Baseline cutoff vs. server time.** An unseen event is alerted only if the
  server's `timeSent` is later than the device time when the baseline was set.
  The feed sends zone-less local wall-clock times (for example `2026-09-30 11:09:53`),
  which are parsed in the device time zone. A device in another time zone, or a
  skewed clock, can silently classify events posted in the first hours after an
  opt-in or re-enable as `olderThanBaseline`. This is not a defect for devices in
  the school's time zone. Revisit it if device tests show early events missing.
- At-most-once: a crash between claim and `show`, or a resume during that window, loses that alert.
- A malformed relevant feed entry blocks that account's ingestion until it leaves the unread feed (documented fail-closed behavior).
- OS scheduling: Doze, App Standby buckets, OEM battery managers, force-stop
  (Android), and BGAppRefresh budget, Low Power Mode, disabled Background App
  Refresh and force-quit (iOS) can delay or prevent runs. Neither platform
  guarantees 15-minute polling.
- iOS before first unlock: the Keychain is unavailable and the run fails. A later OS-granted run is required.

## 5. Verification in this environment

| Check | Result |
| --- | --- |
| New `test/school_notification_keychain_test.dart` (Keychain model mirroring the darwin plugin's query rules: reproduction, upgrade, UI compatibility, no-loss on failed upgrade) | 4/4 passed |
| New service test: unreadable saved login → `credentialsUnavailable`, no request, no account/server in diagnostics | passed |
| Focused notification suites (keychain, service, background, engine, opt-in, UI opt-in) | 135 passed |
| `flutter test --no-pub` (full) | **1,317 passed**, 2 existing skips (`build/issue82_keychain_full_tests.log`) |
| `flutter analyze --no-pub` | No issues |
| `git diff --check` | OK |
| `python tool/check_school_notification_config.py` (new check: shared iOS login read across Keychain classes) | All passed |
| `flutter build apk --debug --no-pub` | Built `app-debug.apk` (`build/issue82_keychain_android_debug.log`) |
| `flutter build apk --release --no-pub` (R8, resource shrinking) | Built `app-release.apk`, 87.1 MB (`build/issue82_keychain_android_release.log`); not installed |
| Config check with merged release manifest (`--merged-manifest …/processReleaseManifest/AndroidManifest.xml`) | All passed |
| iOS build / Swift compile | **Not possible** (no macOS/Xcode). No Swift was changed. |
| Physical Android / iPhone delivery | **Not performed** (no device) |

The Keychain model in the test is derived from reading the plugin's Swift
source. It is not proof of Keychain behavior on a device.

## 6. Physical-device qualification still required

iPhone (signed build, after updating from a build **before** this fix):

1. The saved login still signs in automatically after the update.
2. Settings list the enrolled accounts again.
3. Lock the device, trigger BGAppRefresh with Apple's development procedure
   (`e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"it.bucci.digitalesregister.schoolRefresh"]`).
   The result must not be `credentialsUnavailable`. A new grade or message after
   the baseline must produce a visible notification.
4. Reboot, trigger before the first unlock: failure is allowed, and the login must survive.
5. Account switch, logout/login and password change keep working. Then repeat step 3.

Android (signed release with R8, plus one OEM with aggressive battery management):
run the scenario table in `SCHOOL_NOTIFICATIONS_DEVICE_TESTS.md`. Use
`adb shell dumpsys jobscheduler` to confirm the job, and the settings diagnostics
to tell "worker ran" from "request accepted" from "visible". A requested
notification is not proof of display.

## 7. Issue #82

Issue #82 **must remain open** until all of the following are done:
- Xcode compilation and a signed iOS release qualification;
- a signed Android release qualification;
- validation against a real school API with authorized test accounts;
- physical Android and iPhone delivery tests.

This report does not claim that real delivery was proven.

## 8. Changed files

- `lib/desktop.dart`: class-independent iOS Keychain options for the app storage.
- `lib/school_notification_background.dart`: `SchoolNotificationKeychain`.
- `lib/school_notification_service.dart`: uses it; `credentialsUnavailable` diagnostic.
- `assets/locales/{de,en,it,lld}.json`: one new result text each.
- `test/school_notification_keychain_test.dart` (new), `test/school_notification_service_test.dart`.
- `tool/check_school_notification_config.py`: storage-consistency check.
- `docs/SCHOOL_NOTIFICATIONS.md`, `docs/SCHOOL_NOTIFICATIONS_DEVICE_TESTS.md`, this report.
