# Store privacy checklist — based on repository behavior

Audit date: 2026-10-01. This document prepares review; it does not submit or certify Google Play Data Safety / Apple App Privacy forms. Inspect the final APK/IPA and installed SDK version and reconcile with current store definitions before submission. iOS configuration and device testing are still pending.

| Actual processing | Google Play / Apple categories to review | Purpose and qualification |
|---|---|---|
| Firebase fixed screens, app actions, load/login/sync/filter results | App interactions / product interaction / usage data | Optional Analytics; current v4 + atLeast14 + usage consent. No free-text or raw register content |
| Random installation-local account UUID, automatic SDK installation/session context | User IDs / device or other identifiers | Pseudonymous, not anonymous; account linkage is installation-local, no cross-device matching |
| Sanitized errors/technical keys/logs and SDK-native crash reports | Crash data, diagnostics, possibly other performance data according to the shipped SDK | Optional diagnostics consent independent of Analytics; no account user identifier, grades, school_id, payloads or raw error messages |
| Overall grade average in integer tenths, year/semester, count buckets and stable internal school ID | Personal/education/other data categories under the actual forms | Separate optional academic AND usage consent, atLeast14, non-demo. These are educational statistics; do not describe as individual grade upload or anonymous data |
| Credentials, student/profile/register data transmitted directly to school provider | Account information and education/app functionality categories as applicable | Required user-requested register service; transmission to the school provider must be assessed even without a first-party backend. Legal roles/basis review needed |
| Health-related absence reasons, messages, homework and downloaded documents | Health information / messages / files / other user content as applicable | Necessary register functions only. No telemetry of this content; inspect applicable collection/ephemeral-processing store definitions |
| User calendar sync to device/provider calendar | Calendar / app functionality categories where applicable | Android-only calendar adapter; separate OS permission/requested feature; provider can sync data. Optional telemetry consent does not authorize calendar access |
| Local credentials/settings/notes/cache/attachment copies | On-device-only treatment under applicable disclosure definitions | Distinguish local data from off-device requests, calendar/provider sync and OS backups |
| In-app register notifications and email setting | App functionality and email/account preference where applicable | No active FCM push tokens. Do not disclose invented push collection; review if FCM is later actually added |
| External support, project, update and donation links | Off-device service/network data under applicable rules | Raw exceptions no longer prefill the support form. Users can voluntarily send their own support content; linked services have their own privacy rules |

Checklist for final submission:

- Declare optional SDK data only as actually transmitted after consent; verify fresh-install/restart native traffic and automatic metadata.
- Assess encryption in transit, data linked to a user, required/optional choices, service-provider sharing definitions and deletion support against store wording. Do not infer a “not collected” answer from consent being optional.
- No Google Signals, Ads, remarketing, advertising identifiers, user-provided Analytics data, location instrumentation or Performance Monitoring added. Do not invent advertising purposes or an ATT prompt.
- School ID needs academic consent. “Pseudonymous” is not “not linked” or “anonymous” in disclosure forms.
- Public privacy URL must show the same current notice/contact as the four in-app versions. Confirm URL availability and accessibility before store submission.
- Account-removal behavior is local saved-account removal, not deletion of the school's account or already uploaded Firebase/BigQuery records. Ensure store deletion answers describe actual available processes; establish the manual privacy-request process via the confirmed contact.
- Confirm contacts: Tobias Bucci, Mühlenweg 51, St. Sigmund, Italy (Bolzano); buccitobias774@gmail.com.
- Confirm actual BigQuery retention and contract/transfer/legal details before publication; review the Ladin legal text with a fluent reviewer.

References: [Play Data Safety](https://support.google.com/googleplay/android-developer/answer/10787469), [Apple App Privacy](https://developer.apple.com/app-store/app-privacy-details/), [Firebase privacy](https://firebase.google.com/support/privacy). Forms and Console settings were not changed by this repository work.
