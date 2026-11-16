# Polls (issue #131)

A poll is created and started in the admin portal of the notification server,
announced through the existing app announcements (#78, see
[APP_NOTIFICATIONS.md](APP_NOTIFICATIONS.md)), and voted on in the app or on a
web page. One vote per device. The API is part of the public contract in
[`contract/`](../contract/README.md).

## Design

**A poll owns one announcement.** Starting a poll creates an announcement of the
type `poll` whose title is the question and whose body is a short text that
makes sense without any poll UI. The announcement carries two things:

- `poll`: an optional, additive object (`id`, `type`, `question`, `options[]`,
  `opens_at`, `closes_at`, `show_results`). Clients that know the `type` open
  the in-app poll screen.
- `link`: always an external HTTPS link to the web voting page
  `https://www.digitalesregister.com/umfrage/<id>`. Clients without poll
  support (or with an unknown poll `type`) show the announcement with this
  link, exactly as they show any announcement today. Polls never use
  `link.kind: internal`.

So one announcement serves old and new clients; no `schema_version` bump.
Platform and version targeting reuse the announcement AND/OR rules and are
optional: an old client is never stuck, it votes through the web page.

**Endpoints** (public, anonymous, no login):

| | |
|---|---|
| `GET /api/v1/polls/{id}?lang=` | Question, options, open/closed, and the aggregated result if `show_results` allows it. `ETag`/`304` like the announcements. No identifier is sent. |
| `POST /api/v1/polls/{id}/vote` | `{"option_id", "voter"}`. `200` receipt, `409 already_voted` with the original choice, `410 poll_closed`, `429`, `400 unsupported_client` for a `schema_version` the server does not know. Unknown extra fields are accepted. `attestation` is reserved for Play Integrity / App Attest and ignored today. |

**One vote per device.** The client creates a random installation ID (UUIDv4,
128 bit from a secure random source) the first time the user votes, and stores
it locally. No hardware, advertising or browser fingerprint is read. It is sent
only with a vote. The server stores `HMAC-SHA256(key, poll_id ":" voter)` per
poll, never the raw ID, with a unique constraint `(poll_id, voter_hash)`. The
key comes from the server configuration and is never committed. Hashes of
different polls cannot be linked. A second vote returns `409` with the first
choice, which the client shows as "You voted".

**Results** are aggregated counts per option, updated when a vote is stored.
The admin portal always sees them; `show_results` decides only what voters see.
Votes and hashes are deleted a configurable number of days after a poll closed;
the aggregated counts stay.

**Honest limits.** Reinstalling the app or clearing its storage creates a new
ID, and the same person can vote once in the app and once in each browser. The
results are votes per device, not unique persons. Good enough for informal
school polls, and labelled as such in the admin portal.

## Version safety

The first app release with polls is **2.0.0** (version `X`). Older versions
(1.17.x) have no announcements at all. A server can target an in-app poll
announcement to `app_version >= 2.0.0`, but it does not have to: a client that
does not understand `poll` shows the text and the web link. Builds of 2.0.0
from before this change (the web app until its next deploy, test builds) also
report 2.0.0; they get the web link, which works.

## App

| Part | File |
|---|---|
| `poll` object, poll state, vote receipt | `lib/polls/poll_models.dart` |
| Installation ID | `lib/polls/installation_id.dart` |
| Votes of this device (`poll_id -> option_id`) | `lib/polls/poll_vote_store.dart` |
| `GET` state, `POST` vote | `lib/polls/poll_api.dart` |
| Poll screen | `lib/ui/polls/server_poll_page.dart` |

- Unknown poll `type` or a broken `poll` object: the announcement stays a plain
  announcement with its web link.
- Fail open: no network, a server error or unreadable storage shows "Voting is
  not possible right now" and never blocks anything else. `409` is success.
- A local record of the vote keeps the screen right offline and after a
  restart.
- Works without a school login, in both designs, all themes and layouts.

## Server (private repository)

Admin "Umfragen" section (list, detail with counts, percentages and a timeline,
create/edit drafts, start, close early, duplicate, delete, CSV export), poll
tables in a migration, the vote endpoint with a per-IP limit, retention cleanup,
and the web voting page on the website.
