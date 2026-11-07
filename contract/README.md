# Public API contract

`public.openapi.yaml` and `fixtures/` describe the anonymous notifications API.

| Fixture | Shows |
|---|---|
| `list-typical.json` | Three notifications with internal, external and no link |
| `list-empty.json` | No active notification |
| `list-page-1.json`, `list-page-2.json` | Cursor pagination across two pages |
| `list-critical.json` | Type with `critical: true`, popup needs a manual close |
| `list-important-revision.json` | `attention_revision` raised by an important edit |
| `list-locale-fallback.json` | `lang=it` answered in German |
| `error-*.json` | Error bodies for 400, 429 and 500 |
| `not-modified-304.json` | Conditional request and its `304` exchange (not a body) |

All fixtures match the schemas in `public.openapi.yaml`.
