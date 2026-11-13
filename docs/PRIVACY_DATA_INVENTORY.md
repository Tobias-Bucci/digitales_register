> 2026-10-24 correction: current notice version is **5**. References below to
> v4 and atLeast14 describe the previous policy. Current authorization requires
> a completed v5 decision and the corresponding purpose consent, without an age
> gate. New decisions do not store age. Platform exclusions and data boundaries
> remain. For current iOS provisioning, see [iOS setup](IOS_FIREBASE_SETUP.md).

> 2026-11-07 addition: in-app announcements (issue #78). See the table rows
> "App announcements" and the section "Notification server and Cloudflare". The
> consent version stays **5**: no optional purpose changed, only the description
> of required processing and recipients.

> 2026-11-07 addition: first-sync baseline for announcements (issue #103). One
> boolean inside the existing device-scoped record, see the row "App
> announcements". Nothing is sent to the server and no new key is stored.

> 2026-11-07 addition: design choice (issue #108). One boolean `designChoiceMade`
> in SharedPreferences, next to `tutorial.v3.seen`, records that the user chose
> between the new and the legacy design; the design itself stays `legacyDesign`
> in the settings. Device scoped, kept across logout and app updates, removed only
> with the app data. Not sent anywhere and no analytics event. See the row
> "Settings, favorites, …".

> 2026-11-07 review: the public privacy policy (de, en, it, lld) now matches this
> notice. The open review notes in the notice were resolved: register data stay
> between the device and the school register, announcements rest on legitimate
> interest, GA4 and BigQuery retention are 14 months as confirmed by the owner.

# Privacy data inventory — version 4 (historical audit)

Audited 2026-10-01 against this repository. Controller for this app fork, confirmed by the owner: see the privacy notice in the app. The school/register provider's roles and necessary-processing legal bases require legal review. This is an implementation inventory, not a legal compliance guarantee.

The app uses the selected school's existing API, not a newly introduced first-party telemetry backend. “Local” does not imply anonymous or that OS backups cannot exist. Android app backup is disabled in the manifest; platform/keychain and calendar retention must be considered separately.

| Data / source | Purpose / processing and recipients | Identifiability | Retention and deletion | Basis / optional consent | Platforms |
|---|---|---|---|---|---|
| Username/password and optional second factor, user input | Authentication directly to selected register provider; saved credentials use FlutterSecureStorage (Windows included), encrypted Hive/biometric key storage on other desktops | Directly personal, secret | Saved-account removal / app storage controls; unsaved credentials and cookies held in session memory. OS secure-storage/backup semantics may differ | Necessary requested login; legal basis/roles: Legal review required. No telemetry consent required | Android, iOS, Windows; existing other desktops |
| Session cookies / register authentication, provider | Register requests; Wrapper CookieJar in process memory. No token export to Firebase | Secret, account-linked | Wrapper logout/replacement clears cookies; provider's server retention unknown | Necessary session; Legal review required | Same |
| Profile, account/student identity, class/school information, register API | Display and account functions; saved app state via existing secure writer, provider remains recipient of API requests | Personal; school/class may identify individuals | Cache replacement, saved-account removal, app-data deletion. Provider retention unknown | Necessary requested features; Legal review required | Same |
| Individual grades, subjects, teachers, report cards, API | Register display, canonical local grade calculations and forecasts | Personal education data | Local cache replacement/removal; school/provider duration unknown | Necessary register functions; Legal review required | Same |
| Absences, dates, reasons, API/user submissions | Display, justification and future absence operations with school API | Personal; illness reasons may be health data | Same local/provider distinction; never diagnostic or Analytics input | Necessary requested processing; sensitive-data basis and roles: Legal review required | Same |
| Timetable, lesson topics, homework, class-register entries and course materials, API | Requested educational display and downloads | Personal or contextual education data | Caches/downloads remain until replaced/deleted; provider duration unknown | Necessary functions; Legal review required | Same |
| School messages, confirmation actions and attachments, API | Requested communication functions with register provider | Personal/free text | Local cache/removal; remote message retention set by provider | Necessary functions; Legal review required | Same |
| Settings, favorites, subject aliases, study notes, reminder/assessment plans, user | SharedPreferences and existing locally persisted app state; local functionality. Includes the markers that the intro was seen and a design was chosen (`designChoiceMade`) | Can contain personal free text | Change/remove entries or delete app data; no uniform TTL | Requested local functionality; Legal review required | Same |
| Privacy choices, current notice version, coarse age state and change time, user | One local SharedPreferences record; authorize separate telemetry purposes | Local personal preference; no exact age/birth date/year | New decision replaces record; app-data deletion removes it. Never uploaded as age/consent properties | Local consent management; Legal review required for necessary storage | Same |
| Random UUIDv4 per installation/local saved account; installation namespace | Analytics account separation; encrypted local lookup map. Uploaded UUID never encodes username/email; no cross-device identity | Pseudonymous, not anonymous | Local map until removal/storage deletion. SDK user ID clears on logout/revocation; server history is separate | Usage consent, current v4 and atLeast14 | Firebase only on supported configured mobile/Apple targets; Windows no-op |
| Fixed screens/actions/results and nine allowlisted properties | Optional usage statistics to Google/Firebase; school_id additionally requires academic consent and non-demo | Pseudonymous; automatic SDK app/device/session and network context can identify indirectly | Project-reported GA4 14 months/reset on activity; not a blanket TTL for aggregate reports. Separate BigQuery retention required | Usage consent, current v4 and atLeast14 | Android; iOS only with real Firebase config; existing macOS guarded; no Windows/Linux |
| Canonical total average normalized to integer tenths, year/semester and count buckets | Additional pseudonymous school/grade aggregates to Firebase. No individual grades, subjects, teacher, class or attendance fields | Pseudonymous educational statistics tied to UUID and internal school ID | Local normalized fingerprint deduplicates across sessions; export needs own TTL. No server deletion workflow | Additional academic AND usage consent, current v4 and atLeast14, non-demo, unambiguous school | Same supported telemetry targets |
| Sanitized fixed error codes, filtered Dart symbol frames, fixed technical keys/breadcrumbs; native automatic reports | Crashlytics to Google/Firebase for technical diagnostics; no Crashlytics account user identifier | Technical installation/session identifiers; native reports have platform metadata beyond Dart sanitizer | Disable and delete unsent reports on denial/withdrawal. Google describes 90 days before beginning removal from live/backup systems. Already uploaded reports not removed by local revocation | Diagnostics consent, current v4 and atLeast14 | Android; configured iOS/guarded macOS; Windows/Linux no-op |
| Network protocol entries / Wrapper | Local technical request category and completed/failed state only. No request/response payloads, URL host, query or multipart filename recorded | Minimized technical category; underlying request still contains necessary register data | Bounded existing protocol state; local removal/app storage controls | Necessary troubleshooting UI; no additional collection | Same core platforms |
| Calendar events and sync records / register/user | Explicit sync writes events to selected device calendar using existing native channel. Calendar account provider may sync independently | Personal education/schedule content | Disable/cleanup supported app sync; remove remaining events and cloud copies in calendar provider. Local sync IDs in preferences until removed | Separate calendar permission/user action, not telemetry consent; Legal review required | Android native calendar adapter only; iOS/Windows currently unsupported fallback |
| Downloaded files / local assessment attachment copies | Filesystem and user-chosen external readers; Android external cache copy for opening | May contain personal school documents | Delete attachments/downloads; reader/calendar/provider copies independently | Requested file function; Legal review required | Same core platforms |
| Register notifications and email preference / register API | In-app notifications and provider email setting; `notifications_enabled` reflects known email preference, not push permission | Message content/account preference | Provider retention unknown; cache/account controls | Necessary communication; usage consent only for coarse optional property | Same |
| External links, manual support form, GitHub update queries | Browser/OS links and direct HTTP to external providers; network metadata processed there. Error form has no prefilled raw exception/URL/payload | IP/network context, user-supplied support text | External provider rules; no app-established TTL | Requested support/links/update functionality; Legal review required | Same |
| App announcements, public API | Polling `api.digitalesregister.com` while the app is in the foreground, with `platform`, `app_version` (no build number) and `lang`, plus connection data of any HTTPS request (IP address, user agent). Recipients: the notification server, and Cloudflare as a proxy | Announcements are public and hold no user data. The request is anonymous, but IP addresses are personal data at Cloudflare | Read state, alert state and dismissals in SharedPreferences, device scoped, kept across logout. The same record holds a flag that the first complete list was received; that list is recorded as read and announced so a new installation is not flooded (issue #103). No new key, no content, no identifier. Unread content in a separate cache entry that follows `localDataPolicy`. Read records are removed 180 days after the last listing; dismissal tombstones until app data is deleted | Required for the feature; does not depend on any optional consent and sends no events. Legal basis to be reviewed | Android, iOS, Windows, Linux, macOS; web once a web build exists |

## Notification server and Cloudflare

- In normal operation it stores no IP addresses (memory only, for rate limiting), writes no access log, sets no cookies on the public API and has no analytics. On a server error (5xx) the web server writes the client address, the URL and the request headers without cookies to the system log, which is deleted after 15 days at the latest.
- The server runs on Oracle Cloud Infrastructure in the Milan region (eu-milan-1). Oracle states that it acts as a processor.
- Cloudflare proxies the website and the API: it terminates TLS and sees visitor addresses and request metadata under its own terms. Its answers carry `Report-To` and `NEL` headers.
- Sources for the policy text, read on 2026-11-07: [Cloudflare privacy policy](https://www.cloudflare.com/privacypolicy/) (effective 4 November 2025), [Customer DPA](https://www.cloudflare.com/cloudflare-customer-dpa/) (version 6.4, effective 3 April 2026), [GDPR FAQ](https://www.cloudflare.com/trust-hub/gdpr/), [sub-processors](https://www.cloudflare.com/gdpr/subprocessors/cloudflare-services/).
- The app's own text only reports what Cloudflare states. It makes no legal assessment of those transfers.

## Explicit absences and engineering limits

- No active Firebase Cloud Messaging, push token handling, Firebase Performance, Advertising ID, ATT prompt, Ads linking, remarketing, user-provided Analytics data or precise location collection was found/added. `pubspec.yaml` contains no FCM/local-notification/workmanager dependency. Legacy notification preference cleanup is not active push delivery; README's historic WorkManager statement is superseded.
- Necessary register data are not Analytics/Crashlytics event input. Automatic native crash metadata cannot be filtered by the Dart sanitizer; verify device traffic and crash behavior before release.
- Firebase initialization errors close gates; optional telemetry failures never prevent login/navigation/core operations. One failed initialization is cached for the process.
- Academic statistics use `overallGradeAverage(state)`, the same canonical function as displayed averages, plus eligibility/provenance/completeness checks. Empty grade sets are not contributed.
- Published groups require at least 30 distinct pseudonymous identifiers. This is an internal engineering rule, not a statutory anonymity threshold.
- Google contract applicability, international transfer safeguards, necessary-processing bases and handling of health-related register data require legal review. EU BigQuery location does not prove EU-only Firebase processing.
- Secure local account ID lookup and normalized fingerprints are not sent to Firebase. A person on multiple devices can count as multiple pseudonymous users.

References: [Firebase privacy](https://firebase.google.com/support/privacy), [Store checklist](STORE_PRIVACY_CHECKLIST.md). App notice exists in de/it/en/lld catalogs and includes the confirmed contact.

## Native exports (Issue #12)

The user can explicitly create local PDF/CSV/ZIP copies of currently loaded
register data under Settings → Data export. These may contain grades, messages,
certificate text/tables, calendar entries, lesson content and absences. No export
data is sent to an additional service or included in analytics/logs. Bytes are
created in memory and saved to a user-selected native destination; these copies
are controlled by the user and are not removed when clearing app data or logging
out. iOS requires a temporary native staging copy, cleaned on completion/cancel
(OS-managed if the process terminates). See [Native export](NATIVE_EXPORT.md).
