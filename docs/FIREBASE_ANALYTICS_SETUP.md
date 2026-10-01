# Firebase Analytics setup — privacy version 4

The app reuses the existing Firebase configuration, `AnalyticsService`, `PrivacyController`, `ProductAnalytics`, `DiagnosticsService` and native default-off bootstrap. No SDK dependencies or parallel telemetry services were added.

Startup reads the local privacy decision before attempting Firebase. `TelemetryCapabilities` centralizes production platform policy: Android/iOS/existing macOS adapters are eligible, Windows/Linux no-op. A bootstrap/config/plugin failure is cached for the process and leaves optional gates closed; core functionality continues.

Analytics opt-in order: explicit advertising denials + analytics-storage choice via `setConsent`, then collection enabled, then gated identity/properties/events. Withdrawal closes Dart gates synchronously, disables collection, denies storage, clears all app properties/user ID and resets local Analytics data. Diagnostics have their own consent and unsent-report purge. Unknown/under14 and pre-v4 decisions cannot authorize either SDK.

The stable school ID additionally requires academic consent and non-demo mode **at the central property boundary**, including direct property callers. Account switches clear prior attribution; unambiguous fixed mapping is required. The three purposes remain separate and default denied.

Existing Console configuration from the specification is recorded in [Console configuration](FIREBASE_ANALYTICS_CONSOLE_CONFIGURATION.md); do not duplicate custom definitions, enable ads/Signals, mark academic events as conversions, or add Performance/FCM. No Console writes were performed.

Use [implementation details](ANALYTICS_IMPLEMENTATION.md), [privacy inventory](PRIVACY_DATA_INVENTORY.md), [latest-snapshot SQL](ANALYTICS_BIGQUERY_EXAMPLES.md), [retention tasks](BIGQUERY_RETENTION.md), [iOS setup](IOS_FIREBASE_SETUP.md) and [store checklist](STORE_PRIVACY_CHECKLIST.md). Real-device traffic and symbol/delivery verification remain necessary.
