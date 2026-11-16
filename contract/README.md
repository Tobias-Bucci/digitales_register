# Public API contract

`public.openapi.yaml` and `fixtures/` describe the anonymous notifications API
and, since 1.2.0, polls.

| Fixture | Shows |
|---|---|
| `list-typical.json` | Three notifications with internal, external and no link |
| `list-empty.json` | No active notification |
| `list-page-1.json`, `list-page-2.json` | Cursor pagination across two pages |
| `list-critical.json` | Type with `critical: true`, popup needs a manual close |
| `list-important-revision.json` | `attention_revision` raised by an important edit |
| `list-locale-fallback.json` | `lang=it` answered in German |
| `list-poll.json` | Poll notification: `poll` object plus the external fallback link to the web voting page |
| `list-poll-unknown-type.json` | Poll of a type a client may not know (`ranking`): show it as a plain notification with its link |
| `future-list-extra-fields.json` | Body of a newer server with fields this contract does not define. Not valid against the schemas on purpose: clients must ignore the extra fields |
| `poll-open.json` | `GET /api/v1/polls/{id}`: open poll with its result |
| `poll-closed.json` | The same poll after it closed, with the final result |
| `vote-receipt.json` | `200` of `POST /api/v1/polls/{id}/vote` |
| `vote-already-voted-409.json` | `409` of a repeated vote, with the first choice |
| `error-*.json` | Error bodies for 400, 410, 429 and 500 |
| `not-modified-304.json` | Conditional request and its `304` exchange (not a body) |

Every fixture except `future-*` and `not-modified-304.json` matches its schema
in `public.openapi.yaml`.

## Compatibility rules for polls

- The `poll` object is additive; `schema_version` stays `1`.
- A poll notification always has an external `link` to the web voting page,
  so a client without poll support still works. Polls never use an internal
  link.
- A client renders a poll screen only for a `type` it knows
  (`single_choice`), and treats a broken `poll` object as absent.
- A vote sends `option_id` and `voter`, a random UUID the client created for
  itself, and nothing else. Reading a poll sends no identifier.
- `409 already_voted` is success: it carries the choice stored first.
- Any other error maps to a neutral "voting is not possible right now".
- `attestation` in the vote request is reserved for a later platform
  attestation and ignored today.
