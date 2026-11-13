# Issue #78 implementation audit

Audit of issue #78 ("cross-platform in-app notification center and polling")
against the client code in this repository and the private notification server
(`digitales_register_server`), done on 2026-11-13. The issue text is the
reference; the user's audit brief added the edge cases at the end.

Status values: **done** (code and a passing test or a direct check point to it),
**partial**, **missing**, **wrong**, **unclear** (needs a device, the live server
or a decision to verify). Line references are to `main` at `27465758` (client)
and `e5fe42e` (server).

## Summary

The feature is implemented almost completely, on both sides, with unusually
thorough tests. No requirement was found that is implemented incorrectly.

What is open:

- **Web build (C1, A1):** there is no `web/` folder, so the app has no web
  target at all. The notification code is web-ready (no `dart:io`, sends
  `platform=web`), but "launch on Web" cannot be met or tested.
- **End-to-end smoke test (Q6):** the contract is identical in both repositories
  and the live API matches it (checked today with read-only requests), but no
  automated client test runs against a real server.
- **Device verification (A1):** behaviour is covered by unit and widget tests
  only. A run on real platforms is still to be done (Android emulator and Windows
  are possible here; iOS needs macOS).
- **Authoring guide (S5):** the admin portal and the CLI exist and are secure,
  but no document explains how to write, schedule, edit importantly, expire or
  revoke a notification.
- **Optional `opened` event (P1):** not implemented. The issue calls it optional,
  and the server has no events endpoint by design.

## Baseline

| Check | Result |
|---|---|
| Client `flutter analyze` | No issues |
| Client `flutter test` | 3387 passed, 1 skipped, 0 failed (matches the last known baseline) |
| Server `cargo fmt --check`, `cargo clippy -D warnings` | Clean |
| Server `cargo test` | 196 passed (74 unit, 81 admin lifecycle, 9 contract, 32 public API) |
| Server `apps/web` typecheck, lint, test | 83 passed |
| Server `apps/admin` typecheck, lint, test | 26 passed |
| Contract files | `contract/public.openapi.yaml`, `README.md` and all 12 fixtures are identical in both repos (byte-equal apart from working-copy line endings) |
| Live API, read-only | `GET /api/v1/notifications?platform=android&app_version=2.0.0&lang=de` gave `200` with the documented envelope and no notifications, `ETag: W/"..."`, `Cache-Control: no-cache`, HSTS, `nosniff`, CORS `*` exposing `etag, retry-after`. Sending the `ETag` back gave `304`. `platform=macos` gave `400` with the documented error model |

## Requirements matrix

### UX and product decisions

| # | Requirement | Status | Evidence | Needed |
|---|---|---|---|---|
| U1 | Bell with unread count, opens the center, newest first | done | `lib/ui/server_notifications/server_notification_bell.dart:8`; `ServerNotification.compareNewestFirst` (`server_notification_models.dart:149`); tests `ui_test.dart` group `bell`, `lists newest first with type and unread mark` | – |
| U2 | Detail: title, plain text, type label/color/allowlisted icon, publication time, typed link | done | `server_notification_center.dart:903`, `server_notification_visuals.dart:9` (fallback icon), `:55` (contrast-safe type color); test `shows everything the issue asks for`, `an unknown icon renders the fallback` | – |
| U3 | Regular popup, auto-closes after 6 s (configurable), closing does not read or dismiss | done | `server_notification_popup.dart:21`, `:215`; tests `a regular popup closes itself after about six seconds`, `closing the popup is neither reading nor dismissing` | – |
| U4 | Critical popup (type `critical` flag) needs a manual close, blocks nothing else | done | `server_notification_popup.dart:215` (no timer when any shown item is critical); tests `a critical popup stays until closed by hand`, `the fixture of a critical type needs a manual close`, `it blocks nothing: the app below stays usable` | – |
| U5 | Several new messages make one summary popup | done | `server_notification_popup.dart:188`, `:437`; tests `several new messages make one summary popup`, `one critical among several makes the summary manual`, `a later arrival joins the open popup` | – |
| U6 | Opening the detail reads it; read stays after restart and sync, not new again | done | `server_notification_center.dart:928`; `server_notification_repository.dart:237`; tests `opening a notification reads it`, `survives a restart, and read content leaves the offline cache` | – |
| U7 | Permanent dismiss per device, never returns, even after an important update | done | `server_notification_repository.dart:259`; tombstones checked first (`:73`, `_isVisible`) and never cleaned up; tests `is final, even after an important edit and a restart`, `tombstones are never cleaned up, read records are`, `a failed read cannot erase tombstones with the next write` | – |
| U8 | Edits update in place; routine edits do not re-alert, important ones (`attention_revision`) re-alert read, non-dismissed items | done | `server_notification_repository.dart:94`; tests `a routine edit does not alert a read notification`, `an important edit alerts again and makes it unread`, `the fixture of an important revision re-alerts` | – |
| U9 | Expired, revoked, out-of-audience removed after sync; known expiry filtered offline | done | `server_notification_repository.dart:275` (expiry timer), `_removeExpired`; tests `revoked and out-of-audience items go with the next sync`, `known expiry is filtered offline, also from the cache`, `an open app drops it at the moment it expires, also offline` | – |
| U10 | App languages, theme, screen size, navigation, a11y (keyboard, focus, screen readers, contrast); German fallback | done | 29 `appNotifications.*` keys in all four locale files, German merged in as fallback (`lib/i18n/app_localizations.dart:434`); content fallback is the server's (`apps/api/src/models.rs:226`); tests `tap targets and contrast meet the guidelines`, `Escape closes, F6 reaches it by keyboard`, `is announced and labelled for screen readers`, `text at 200 % on a 320 px phone does not overflow`, `the center renders in $locale` | – |
| U11 | No HTML/rich text/code/attachments/native notifications/scripts; links only | done | `cleanServerNotificationText` (`server_notification_models.dart:21`), `Text`/`SelectableText` only; tests `renders markup as plain text`, `control and direction characters are removed` | – |
| U12 | Public announcements, AND/OR targeting by platform and semver; not confidential | done | Server `apps/api/src/audience.rs`, `snapshot.rs:122`; tests `audience_rules_filter_per_platform_and_version`, `a_corrupt_audience_rule_fails_closed`; client sends only `platform`, `app_version`, `lang` (test `sends exactly the contract parameters and nothing identifying`) | – |
| U13 | Works signed out | done | Corner bell on the login route (`lib/main.dart:445`, `server_notification_bell.dart:80`); popup host above the navigator (`lib/main.dart:517`); test `without a shell, as signed out, it opens as before` | – |

### Polling and lifecycle

| # | Requirement | Status | Evidence | Needed |
|---|---|---|---|---|
| L1 | Initial request once the app is ready, refresh on return with a freshness window | done | Started after the first-frame init and the launch gate (`lib/main.dart:139`), so it cannot delay start-up; resume uses a 60 s freshness window (`server_notification_poller.dart:117`); tests `resume refreshes stale data at once`, `resume within the freshness window fetches nothing extra` | – |
| L2 | Poll every 300 s, server suggestion bounded | done | `server_notification_poller.dart:11`, `clampInterval` 60 s to 1 h; tests `the default is five minutes`, `a too eager server cannot speed the client up` | – |
| L3 | One poller, no overlap, timers cleaned up, nothing in the background | done | `start()` idempotent (`:104`), `_run` single in-flight future (`:171`), `stop`/`dispose`; tests `one poller: a second start changes nothing`, `calls never overlap`, `nothing runs in the background`, `stop cleans up the timer` | – |
| L4 | Resume on foreground, lifecycle on all five platforms | partial | `server_notification_service.dart:105` maps `hidden`/`paused`/`detached` to background, `inactive` keeps polling; test `inactive keeps polling, hidden and paused do not`. Behaviour on real Android/iOS/Windows/Linux not yet observed, web has no build (see A1) | Device smoke test (Phase 4) |
| L5 | Timeout ~10 s, exponential backoff with jitter, rate limits, no storms | done | `server_notification_api.dart:70`; `server_notification_poller.dart:53` (30 s to 30 min, equal jitter), `Retry-After` up to 24 h, `4xx` waits 1 h; tests group `backoff`, `429 and Retry-After`, `quick switching between apps cannot cause a storm` | – |
| L6 | Versioned GET, `ETag`/`If-None-Match`/`304`, expiry still applied on `304`, validator per selection | done | `server_notification_api.dart:138`, `:183`; `server_notification_repository.dart:148` (validator only for the same selection and a complete local copy); tests `sends the validator and reports 304 as unchanged`, `304 still applies known expiry`, `a validator is not reused for another selection`, `a 304 after a restart cannot lose read items` | – |
| L7 | Complete set with cursor pagination, no silent overflow; empty/offline/timeout/malformed/4xx/5xx safe; never blocks the app | done | `_walk` (`server_notification_api.dart:126`) returns nothing for a partial walk, restarts once on a stale cursor, caps loops; tests group `cursor pagination`, group `failures`, `a failed sync is a note, not an error page` | – |
| L8 | Deduplicate by id, `revision`, `attention_revision`; no alert on every poll | done | `byId.putIfAbsent` (`server_notification_api.dart:157`); `markAlerted`; tests `new notifications are pending once, across polls and restarts`, `nothing is announced twice` | – |

### Local persistence

| # | Requirement | Status | Evidence | Needed |
|---|---|---|---|---|
| D1 | Read state per device only, no identifiers | done | `server_notification_store.dart:97`; test `it uses no identifier of the user, account or device` | – |
| D2 | `read_attention_revision` per id | done | `ServerNotificationRecord.readAttentionRevision`; test `the read revision is kept per notification` | – |
| D3 | Dismissed ids durable, checked first | done | See U7 | – |
| D4 | Only unread content cached offline | done | `_write` (`server_notification_repository.dart:308`) stores `_items.values.where(isUnread)`; follows the "save data on device" setting (`localDataPolicy`); tests `device state holds no content`, `with saving of data turned off, no content is written` | – |
| D5 | Read items reappear from the next online fetch after restart | done | Validator withheld when the local copy is incomplete (`:148`); test `a 304 after a restart cannot lose read items` | – |
| D6 | Known expiry offline, revocation only after reconnect, limitation explained | done | See U9; documented in `docs/APP_NOTIFICATIONS.md` ("Offline limits") | – |
| D7 | Durable cross-platform storage, schema version, cleanup, storage errors | done | `SharedPreferences` behind `ServerNotificationStorage`; `version` field; damage tolerated per entry (`server_notification_store.dart:131`); read records removed after 180 days (`server_notification_repository.dart:14`); tests group `storage` | – |
| D8 | Scoped to the installation, not reset on login/logout | done | test `state is per installation, so accounts do not matter`, `works with real shared preferences, and login is irrelevant` | – |

### API contract and configuration

| # | Requirement | Status | Evidence | Needed |
|---|---|---|---|---|
| C1 | Base URL from build configuration, HTTPS only; platforms `web`, `android`, `ios`, `windows`, `linux`; accurate semver | partial | `DR_NOTIFICATIONS_BASE_URL`, `DR_NOTIFICATIONS_ENABLED` (`server_notification_config.dart:19`), non-HTTPS turns the feature off; version without build number. **Web**: the code sends `platform=web`, but the repo has no `web/` target, so no web client exists. **macOS** has no API value, so the feature is off there (`server_notification_config.dart:46`) | Decide on web (own issue recommended) |
| C2 | Schema validation, unknown versions/fields, `https://` only, internal allowlist, plain text, icon fallback | done | `ServerNotificationPage.parse` (`server_notification_models.dart:239`), `validateExternalNotificationUrl` (`server_notification_links.dart:36`), route allowlist (`:7`); tests group `schema validation`, `links`, `allowlists match the published contract` | – |
| C3 | Public contract and fixtures, client builds without the private repo | done | `contract/` in this repo, identical to the server's | – |
| C4 | Client and server agree on fields, types, status codes, headers, timing | done | Fixtures byte-equal; route keys equal (`database/migrations/0001_init.sql:166` on the server vs `serverNotificationRouteKeys`); live response checked today. No automated guard against future drift: the client CI cannot see the private repo | See Q6 |

### Analytics and privacy

| # | Requirement | Status | Evidence | Needed |
|---|---|---|---|---|
| P1 | Optional `opened` event via `POST /api/v1/events` | missing (optional) | Not implemented; the server has no events endpoint and its brief excluded analytics (`docs/APP_NOTIFICATIONS.md`, "Not implemented") | Decide: drop or defer |
| P2 | No user names, grades, schools, accounts, device ids | done | test `it uses no identifier of the user, account or device`, `sends exactly the contract parameters and nothing identifying` | – |
| P3 | Fetches work without analytics consent; analytics follow consent | done | test `fetches without any consent and sends the version bare`; the feature cannot reach analytics or diagnostics at all (`test/server_notifications/privacy_boundary_test.dart`) | – |
| P4 | Privacy disclosure reviewed | done, legal basis open | `docs/PRIVACY_DATA_INVENTORY.md:54`, notice v5 (`docs/PRIVACY_IMPLEMENTATION.md`); the inventory itself says "Legal basis to be reviewed" | Your legal review |
| P5 | Aggregated server event counts, bounded offline queue | n/a | No events exist, so nothing is counted or queued | – |

### Server (`digitales_register_server`)

| # | Requirement | Status | Evidence | Needed |
|---|---|---|---|---|
| S1 | Endpoint with `ETag` and correct `304` | done | `apps/api/src/public/mod.rs:104`, weak comparison `:96`, collection-wide validator `public/snapshot.rs:133`; tests `etag_is_stable_and_gives_304_without_a_body`, `first_page_etag_covers_changes_on_later_pages`, `etag_differs_per_language_and_audience`; live check | – |
| S2 | Data model: ids, timestamps, severity, localized texts with German fallback, link, expiry, targeting | done | `database/migrations/0001_init.sql:108`; `models.rs:226`; tests `locale_selection_and_german_fallback`, `scheduled_items_appear_and_expired_items_vanish_on_time_without_invalidation` | – |
| S3 | Input validation, safe links | done | `validate.rs:33` (text), `:142` (URL), `admin/notifications.rs:155` (internal keys from the seeded table); unit tests in `validate.rs`, `html_stays_inert_plain_text` | – |
| S4 | Rate limiting, caching, cheap `304` path | done | In-memory snapshot and rendered-page cache (`public/snapshot.rs:289`), no database work per poll; per-IP token bucket and concurrency cap (`public/ratelimit.rs:55`); tests `rate_limit_answers_429_with_retry_after`, `cache_serves_mutations_immediately_and_outside_writes_within_the_ttl`; `deploy/loadtest-server.sh` | – |
| S5 | Authoring: create, edit, schedule, expire, revoke; documented and secure | partial | Admin portal (`apps/admin/src/screens/Editor.tsx`, `List.tsx`, `Types.tsx`), password plus TOTP, CLI bootstrap/reset (`docs/operations.md`, "First admin account"); 81 lifecycle tests. **No guide** explains publishing, important edits, scheduling, expiry, revoke-is-final, duplicate, audience rules or critical types | Write `docs/publishing.md` in the server repo |
| S6 | Logging without personal data | done | `server.rs:99` logs method, path, status, duration only; `docs/operations.md` "Logs and privacy" (5xx entries by Caddy keep an IP for at most 15 days, disclosed) | – |
| S7 | CORS, security headers, TLS, error responses | done | `public/mod.rs:30`; tests `cors_*`, `errors_carry_cors_headers_too`, `unknown_routes_and_methods_use_the_error_model`; HSTS and `nosniff` seen live | – |
| S8 | Server tests for endpoint, `ETag`/`304`, validation | done | 196 Rust tests, see baseline | – |

### Quality

| # | Requirement | Status | Evidence | Needed |
|---|---|---|---|---|
| Q1 | Polling with a fake clock, `ETag`/`304`, backoff | done | `test/server_notifications/poller_test.dart`, `api_test.dart` (fake clock, mock HTTP) | – |
| Q2 | Read/dismiss persistence, offline cache, server down | done | `repository_test.dart`, `fresh_install_test.dart` | – |
| Q3 | Summary popup, critical popup, link validation | done | `ui_test.dart`, `contract_models_test.dart` | – |
| Q4 | Pagination, empty, error, offline, timeout covered | done | `api_test.dart` groups `cursor pagination`, `failures` | – |
| Q5 | Feature and API documented, how to publish | partial | `docs/APP_NOTIFICATIONS.md`, `contract/README.md`, `contract/public.openapi.yaml`; publishing guide missing (S5) | See S5 |
| Q6 | Contract/integration tests on the published schema; end-to-end smoke test against the backend | partial | Fixtures parse in the client (`contract_models_test.dart`); the server validates fixtures and live responses against the schema (`apps/api/tests/contract.rs`). No automated client test against a running server; today's live check was manual | Opt-in client test against a real server URL |

### Platforms and acceptance

| # | Requirement | Status | Evidence | Needed |
|---|---|---|---|---|
| A1 | Initial launch on Web, Android, iOS, Windows and Linux fetches; resume refresh works | unclear / missing (web) | Unit and widget tests only. Web has no build target. iOS needs macOS | Android emulator and Windows smoke test here; iOS, Linux and web by you or later |
| A2 | Normal use works with the server down | done | Fails open everywhere (`server_notification_service.dart:59`); tests `offline is a transient failure`, `a failed sync is a note, not an error page`, `read failure leaves a working, empty repository` | Confirm on a device (A1) |

### Edge cases from the audit brief

| # | Case | Status | Evidence |
|---|---|---|---|
| E1 | Clock changes, time zones | done | Expiry uses the device clock corrected by `server_time` (`server_notification_repository.dart:48`, `_apply`); times shown in local time; test `a wrong device clock does not hide what is active` |
| E2 | App update with old stored state | done | Tests group `existing installations after the update`, `a cache of another version is dropped, state of a newer one is read` |
| E3 | First run | done | Backlog adopted quietly (#103), `fresh_install_test.dart` |
| E4 | Logout, login with another account | done | See D8 |
| E5 | Many notifications at once | done | One summary popup; pages of 100 up to 50 pages; list builds lazily (`the list builds only what is in view`) |
| E6 | Very long text, special characters, emoji | done | Limits 120/2000 code points on both sides; tests `overlong text is cut, by characters`, `text at 200 % on a 320 px phone does not overflow` |
| E7 | Very small screens | done | Tests at 320 px with 200 % text, popup capped at 40 % of the height |

## Risks and observations (not failures)

1. **No contract drift guard.** Both copies are equal today, but nothing fails
   when one side changes. The client's CI cannot read the private repo.
2. **Unexpected errors are silent.** Expected failures (network, `4xx`, `5xx`)
   are handled and must stay quiet. Programming errors are swallowed too
   (`server_notification_poller.dart:195`, `server_notification_service.dart:59`),
   because `privacy_boundary_test.dart` forbids the feature from importing
   `diagnostics_service`. They would never show up in Crashlytics.
   *Fixed:* the service and the poller now pass such errors to
   `onUnexpectedError`, which `lib/main.dart` connects to the consent-gated
   diagnostics (category `notification`, sanitized stack). Network and server
   failures are still not reported, and the feature folders still import no
   diagnostics.
3. **Critical backlog on a fresh install is silent.** By the #103 design, a
   critical message that is already active when someone installs the app is
   listed without popup or badge. *Changed on your decision:* critical backlog
   items now stay unread and pop up once; normal backlog stays quiet.
4. **Popup during the launch reveal.** Polling starts when the launch gate opens,
   so with a fast network a pending popup can appear while the logo overlay is
   still fading. The 6 s timer leaves enough time to read it; not observed on a
   device.
5. **Pull to refresh ends at once.** `RefreshIndicator.onRefresh` does not wait
   for the sync, so the spinner disappears before new data arrives.
6. **macOS** builds show no announcements because the API has no `macos` value.
   The issue does not ask for macOS.
