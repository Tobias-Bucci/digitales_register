# App announcements

Public announcements from the notification server, shown in the app (issue #78).
The API is described in [`contract/`](../contract/README.md). They are separate
from the school's register notifications (`lib/ui/notifications_page.dart`) and
from the local reminders, which is why the app calls them "App-Mitteilungen".

## Where things are

| Part | File |
|---|---|
| Models and validation | `lib/server_notifications/server_notification_models.dart`, `..._links.dart` |
| Configuration | `lib/server_notifications/server_notification_config.dart` |
| HTTP, ETag, pagination | `lib/server_notifications/server_notification_api.dart` |
| Local state | `lib/server_notifications/server_notification_store.dart` |
| Merging server and local state | `lib/server_notifications/server_notification_repository.dart` |
| Timing | `lib/server_notifications/server_notification_poller.dart` |
| App lifecycle, singleton | `lib/server_notifications/server_notification_service.dart` |
| Bell, center, detail, popup | `lib/ui/server_notifications/` |

## Configuration

| Build define | Default | Effect |
|---|---|---|
| `DR_NOTIFICATIONS_BASE_URL` | `https://api.digitalesregister.com` | API origin. Anything but plain HTTPS turns the feature off |
| `DR_NOTIFICATIONS_ENABLED` | `true` | `false` removes the bell and all requests |

## Rules worth knowing

- **Failing open.** Nothing here can block the app: no platform value, a bad
  version, a server that is down, or storage that does not work all leave the app
  as it is, at worst without announcements.
- **`304` and the unread-only cache.** Read content is not cached, so after a
  restart the app may lack parts of the collection. It then omits `If-None-Match`,
  because a `304` would confirm a list it cannot show. See
  `ServerNotificationRepository._validatorFor`.
- **ETags of later pages differ.** The server hashes the cursor into them, so only
  the first page's validator means anything, and pages must not be compared.
- **Expiry uses the real clock**, corrected by the last `server_time`, never
  `appClock`, whose simulated date only applies to the demo mode.
- **Alerts.** A popup is due if `attention_revision` is above both the read and
  the already announced revision. That is stored when a popup is actually shown,
  so a message that arrived behind the app lock is not lost.
- **The backlog of a new installation is quiet (#103).** No saved device state
  means a fresh installation (or deleted app data). Its first complete `200`
  list is recorded as read and announced, so it is listed in the center without
  popup or badge. Only what a later sync adds alerts. It is decided by
  membership in that list, not by time, so no device clock or publishing moment
  can let a backlog item through. A failed or partial sync, or a `304`, sets
  nothing. Saved state from earlier versions, and state that cannot be read,
  counts as baselined, so existing users keep their unread notifications. The
  school's feed needs none of this: its unread state is the school's own,
  shared with the website and other devices, and its system notifications have
  their own quiet first baseline per account.
- **Dismissal is final.** Tombstones are checked first and never cleaned up.
- **No events.** The routes of this feature have no name on purpose: the navigator
  observer turns route names into screen events.
- **Offline limits.** A client cannot learn about a revocation while it is offline.

## Timing

Foreground only. The suggested `poll_after_seconds` is bounded to 60 s to 1 h, the
default is 5 min. Returning to the app fetches if the last request is at least 60 s
old. Failures back off from 30 s up to 30 min with jitter, and `Retry-After` is
honoured up to 24 h; `4xx` waits an hour. No path, including pull to refresh, can
run before a backoff has passed. `AppLifecycleState.inactive` keeps polling, because
that is a visible desktop window without focus.

## Not implemented

The optional `opened` event: the server has no events endpoint. It would have to
follow the existing analytics consent.

## Platforms

Unit and widget tests cover the behaviour. There is no `web/` folder in this
repository, so no web build exists yet; the new code contains no `dart:io` and sends
`platform=web` there. macOS has no value in the API, so nothing is fetched there
and the bell is not shown.
