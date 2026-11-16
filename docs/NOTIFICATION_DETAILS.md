# Detailed, localized school notifications — Issue #133

Builds on the personal school notifications of #82 (`SCHOOL_NOTIFICATIONS.md`).

## Findings (2026-11-16)

- Personal notifications are produced **on the device only**. A WorkManager job
  (Android, 15 min) or BGAppRefresh (iOS, OS-chosen) signs in with the login saved
  in secure storage, reads the school's `api/notification/unread` feed and shows
  a local notification for new `grade` and `message` entries. While the app is
  open, a 3-minute foreground refresh keeps the in-app feed current quietly.
- The notification text was already built from the **app language**
  (`appLanguageController`), but only as generic text ("A new assessment has been
  published").
- The notification server (separate repository) only serves general app
  announcements that the app polls. It has no device registration, no FCM/APNs
  sender and never sees school credentials or school data.

## Design

The text is built locally from the app's own localization files. No server
change and no new data flow:

- the app language and the subject translation setting are read in the
  background worker, so the text follows the app, not the system language;
- there is nothing to register with a server and old clients keep working;
- the school password never leaves the device.

**Server-side detection and push were not implemented.** The server could only
detect new grades if it held every student's school password and polled the
school servers itself. That would change the security model (passwords leave the
device, the server becomes a high-value target, privacy policy changes), so it is
reported as a decision for the owner instead. A credential-free middle ground is a
periodic *wake-up* push (FCM high-priority data message / APNs background push)
that only tells the device to check; it needs FCM + an APNs key, a device token
registration endpoint and privacy policy changes, and iOS still throttles
background pushes.

### Detection

Per background check and account:

1. Sign in, read the unread feed (as before). New categories besides `grade` and
   `message`: `absence` and `observation` entries become **other school
   events**. Malformed entries of these new types are ignored instead of
   failing the check.
2. With details on and grades enabled, read the past dashboard
   (`api/student/dashboard/dashboard`, `viewFuture: false`) when the feed has a
   new grade or the snapshot is older than an hour.
   It gives subject and value of new grades (the feed's `objectId` is the
   dashboard grade id, as the in-app event cards already use) and reveals
   changed or deleted grades.
3. With homework and tests enabled, read the future dashboard (`viewFuture:
   true`) at most hourly.

An account with details off and only grades/messages makes the same two
requests per check as before.

Dashboard requests are optional: a failure or time-out keeps the feed result and
falls back to generic text. The dashboards are kept as an encrypted per-account
snapshot (same AES Hive box as the event history), and diffed:

- the first snapshot is a quiet baseline;
- a grade whose value changes → "Grade changed: old → new";
- a grade missing while its day is still in the response → "Grade removed"
  (a grade that scrolled out of the window is not a deletion);
- new teacher homework (`lessonHomework`) and tests (`gradeGroup`) → "New homework"
  / "New test". User reminders are ignored.

Every notified snapshot event has a key (`c:<id>:<old>:<new>`, `d:<id>`,
`n:<id>`). Keys are kept (last 1000) and never notified again. Feed events keep
the existing identity history, so the same event is never shown twice, also
across the foreground refresh and repeated background runs.

### Text

`lib/school_notification_content.dart` is pure and unit-tested:

- one notification per category (grades, messages, homework & tests, other) and
  account per check; several events are grouped with a count title and one line
  per event (Android inbox style, iOS multi-line body, at most 5 lines plus
  "+n more");
- grades are formatted per language: `8`, `8+`, `9-`, `8,5` (de/it/lld) or `8.5`
  (en);
- an event without data (dashboard unreachable, unknown format) falls back to the
  previous generic text.

### Privacy

New per-account setting **Show details in notifications**:

- accounts that accepted notifications before this change keep generic text
  (they agreed to "values stay hidden") until they enable it;
- accounts that opt in now get details on; the opt-in text says so;
- off → the exact previous generic texts, on every screen including the lock
  screen. Android notifications stay `VISIBILITY_PRIVATE`, so the system setting
  "hide sensitive content" also hides details on the lock screen; on iOS the
  system "Show previews" setting applies.

### Reliability

- Android: unique periodic WorkManager work, 15 min (OS minimum), network
  constraint, exponential back-off from 1 min. WorkManager persists it over
  reboots (its own boot receiver) and app updates; every app start re-registers
  it with the `update` policy.
- Settings show whether the device optimizes battery use for the app, with a
  button to the system list of battery optimizations (no special permission).
- Per-account back-off after consecutive network/server failures: 0, 15, 30, 60,
  120 min (max). Authentication failures pause until the next app sign-in, as
  before. Offline runs are prevented by the network constraint.
- iOS: BGAppRefresh (earliest 15 min) stays; the 20 s round skips dashboard
  requests if less than 8 s remain.
- A hidden debug page (long-press "Background and diagnostics") shows the last
  check time, result and the last 30 checks.
