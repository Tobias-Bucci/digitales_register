# Architecture

A map of `lib/` for people (and agents) who change the code. It describes how
the code is organized today and the rules that keep it that way. Feature
behavior is documented in the other files of `docs/`.

## State and data flow

The app uses Redux through `built_redux` and `flutter_built_redux` (local forks
under `packages/`). Do not add another state-management approach.

| Layer | Where | Role |
|---|---|---|
| State | `app_state.dart`, `data.dart` (+ generated `*.g.dart`) | Immutable `built_value` state and server data. `serializers.dart` lists what is persisted. |
| Actions | `actions/` | One `*Actions` class per feature. |
| Reducers | `reducer/` | Pure state changes per feature. |
| Middleware | `middleware/` | Side effects: network, storage, navigation. |
| Selectors | `app_selectors.dart` | Values derived from the state (grade averages, filtered homework, ...). |
| Containers | `container/` | Connect the store to a widget: build a view model, pass callbacks. |
| UI | `ui/`, `tutorial/` | Widgets. Most get data and callbacks from a container; some dispatch through the global `actions`. |

`main.dart` creates the store, the navigator keys and the global `actions`.

### The middleware library

`middleware/middleware.dart` is one Dart library split into `part` files, so
that its private session and cache helpers stay private:

- per feature: `absences`, `calendar`, `certificate`, `dashboard`, `grades`,
  `login`, `messages`, `notifications`, `pass`, `profile`, `routing`, `settings`;
- shared concerns: `session` (which account a load belongs to),
  `runtime_cache` (freshness, coalesced loads), `page_payloads`,
  `course_materials`, `downloads`, `study_data`, `persistence`, `local_data`,
  `analytics`.

`middleware.dart` itself holds the shared state, the assembly of all
middleware, error and offline handling, account loading and start-up.

The routing middleware pushes pages, so the middleware library imports UI. That
is the established design. Services and domain code elsewhere should not show
widgets, dialogs or routes: when they need the user, they take a callback (for
example `Wrapper.onRequestTwoFactorCode`). Known exceptions that remain:
`android_widget/android_widget_service.dart` pops to the dashboard through the
navigator keys, and `wrapper.dart` and `biometric_app_lock.dart` use globals of
`main.dart` (`actions`, `tr`). `theme/` and `i18n/` use Flutter types by nature.

## Where things live

Feature folders group the non-UI code of one feature:

| Folder | Content |
|---|---|
| `android_widget/` | Snapshot and platform channel of the Android home-screen widget |
| `export/` | Data export (CSV, PDF) |
| `grades/` | Grade math: averages, categories, forecast, history, statistics, target grade |
| `i18n/` | Languages and `AppLocalizations` (`context.l10n`) |
| `polls/`, `server_notifications/` | App announcements and polls from the notification server |
| `reminders/` | Local reminders and their notifications |
| `study_data/` | Learning notes per account and their migration |
| `theme/` | Palette and design tokens |
| `web_app/` | Web-only entry points and routing |

Cross-cutting services (network `wrapper.dart`, analytics and diagnostics,
persistence, calendar sync, school notifications) are still files in `lib/`.

Most pages exist in two designs that users choose between in the settings:
`x.dart` (Legacy) and `x_new.dart` (new design), often as a `part` of the
Legacy file. Both stay; share logic between them instead of copying it. The
settings sub-pages are parts in `ui/settings/`.

## Rules that are easy to break

- **Background entry point.** `schoolNotificationDispatcher` in
  `school_notification_service.dart` is registered with Workmanager. The
  platform keeps a callback handle that names the function and its library.
  Moving or renaming either breaks background checks of an installed app until
  it is opened again.
- **Tests that read source by path.** `test/local_data_inventory_test.dart`
  lists every file that writes to SharedPreferences, and the privacy-boundary
  tests in `test/polls/` and `test/server_notifications/` scan their folders.
  Update them when code moves; a new preference key must be classified there.
- **Polls stay apart from analytics.** Nothing in `polls/` or `ui/polls/` may
  import analytics, diagnostics, Firebase or account data (enforced by test).
  Shared helpers for them must not import the app (see `random_uuid.dart`).
- **Generated code.** `*.g.dart` is not committed. Run
  `dart run build_runner build --delete-conflicting-outputs` after changing a
  `built_value` class.
- **Persisted formats.** Storage keys, serializer names and translation keys
  are read from existing installations; renaming them needs a migration.
