# Refactoring report

Branch `refactor/full-codebase-cleanup`, based on `main` at `c3d4230b`
(identical to `origin/main` when the work started; working tree clean).
Date: 2026-11-17. Flutter 3.47.7, Dart 3.13.5.

All numbers below were measured unless they are marked as estimates.

## A. Executive summary

**Starting point.** A mature Flutter app with a consistent Redux architecture
(`built_redux`), a large and well-maintained test suite (3,531 passing tests)
and a clean analyzer. Its weaknesses were concentrated in a few places:

- Two god files: `lib/middleware/middleware.dart` (3,160 lines, 79 imports,
  the most connected node of the graph with degree 836) mixed caching,
  course-material downloads, page payloads, learning notes, persistence, file
  downloads and analytics middleware; `lib/ui/settings_page_widget.dart`
  (3,606 lines) held the settings page and all of its sub-pages.
- Service code that showed UI: the analytics service contained the whole
  consent dialog, the network wrapper opened the two-factor dialog through the
  global navigator, the Android widget snapshot imported UI colors, and
  `util.dart` (imported by 45 files) pulled in Material for one helper.
- Copies of the same logic between files and between the Legacy and new
  designs, dead code (an unreachable donation page with its images and
  texts, a stale copy of the homework filter), and a logging function that
  discarded its input while its callers still computed it.
- A flat `lib/` root with about 70 unrelated files.
- Two real defects: a crash-prone dialog (controllers disposed while the
  dialog still used them) and missing `mounted` checks after dialogs.

**What changed.** 15 commits before this report: the two god files were split into cohesive
`part`s; four layering leaks were removed (service code imports no widgets
any more, measured with the graph); two bugs were fixed with a regression
test; duplicated logic was consolidated into shared helpers; dead code and
no-op logging were removed; four self-contained groups of files moved into
feature folders; an architecture map was added; the knowledge graph was
updated.

**Final state.** Analyzer clean, all 3,532 tests pass (the 3,531 existing
ones plus one new regression test), formatting unchanged apart from files
that were already unformatted before. No behavior, persisted format, route,
translation text or public package API was changed intentionally, except the
two bug fixes.

**Remaining major concerns** (section H): `SchoolNotificationService` is a
1,700-line class; three pages share a copy-pasted loading state machine; the
network wrapper still reports offline state through the global store.

## B. Codebase statistics

| Measure | Value |
|---|---|
| Dart files in `lib/` (without generated) | 287 → 305 (measured) |
| Lines in `lib/` (without generated) | 99,628 → 99,620 (measured) |
| Dart files directly in `lib/` | 70 → 57 (measured) |
| Files changed vs `main` (without `graphify-out/`) | 146: 102 modified, 20 created, 10 deleted, 14 renamed (measured, `git diff -M`) |
| Lines changed vs `main` (without `graphify-out/`) | +5,796 / −5,791 (measured; most are moves) |
| Files analyzed by the four audit agents | about 290 `lib/` files plus tests and platform folders (estimate) |
| God files split | 2 (`middleware.dart` 3,160 → 919 lines, `settings_page_widget.dart` 3,606 → 1,699 lines) |
| Layering leaks removed | 4 service files no longer import UI or show dialogs (graph: non-UI → UI import edges from service files 3 → 0) |
| Duplicate implementations consolidated | 9 groups (21 copies) — see D |
| Dead code removed | 1 page, 9 images (≈94 KB), 33 texts × 4 languages, 9 unused declarations, 1 commented-out function, 1 no-op logging function with 20 call sites |
| Bugs fixed | 1 crash-prone dialog, 8 unguarded state updates after an await, 1 leaked controller, 1 possible queue deadlock |
| Tests | 3,531 → 3,532 (1 regression test added, 0 removed or weakened) |

The total size of `lib/` barely changed: the cleanup commits removed about
455 lines net (measured per commit), which is offset by the licence headers,
`part of`/import preambles and file comments of the 19 new files (about 410
lines, measured) and the new dialog widget. The value of this work is in
structure, not in line count.

## C. Architecture

**Original architecture.** Redux with `built_redux`: actions, reducers,
middleware (side effects, network, navigation), selectors, containers that
connect the store to widgets, and widgets in `ui/`. Two designs (Legacy and
new) live side by side and are chosen by the user. This architecture is
consistent and was kept; no state-management or dependency change was made.

**Main clusters** (Graphify communities): middleware and actions, domain
models, settings, auth layout, demo backend, selectors, school
notifications, login and accounts, dashboard, design tokens, calendar,
grades, absences, network wrapper, server notifications.

**Hotspots addressed.**

1. `middleware.dart` is now the library file plus seven new parts next to
   the existing per-feature parts: `runtime_cache`, `page_payloads`,
   `course_materials`, `study_data`, `persistence`, `downloads`,
   `analytics`. The library file keeps the shared state, the middleware
   assembly, error/offline handling, account loading and start-up.
   `part`s keep the private session and cache helpers private, so the split
   is a pure move (checked by script: every original line appears exactly
   once).
2. `settings_page_widget.dart`: the sub-pages moved to parts in
   `lib/ui/settings/` (subject colors, grade averages, subject nicknames,
   substitute teachers, favorite subjects, calendar sync, shared
   add-subject pieces).

**Separation of responsibilities (layering).**

| Before | After |
|---|---|
| `analytics_service.dart` contained the consent dialog (≈350 lines of widgets) | `ui/privacy_consent_dialog.dart`; the service imports no Flutter UI |
| `wrapper.dart` opened the 2FA dialog via `navigatorKey` | `Wrapper.onRequestTwoFactorCode` callback, set by the sign-in middleware; dialog in `ui/two_factor_dialog.dart`; wrapper imports `foundation` only |
| `android_widget_snapshot.dart` imported `ui/grade_colors.dart` | pure `grades/grade_category.dart` |
| `util.dart` imported Material for one widget helper | helper is private to its only caller; util imports `foundation` |
| `biometric_app_lock.dart` held the controller and two widgets | widgets in `ui/biometric_app_lock_overlay.dart` |
| `diagnostics_service.dart` imported Material | `widgets` (only `NavigatorObserver` is used) |

**Directory organization.** New feature folders, following the existing
`polls/`, `export/`, `server_notifications/`: `grades/` (6 files),
`reminders/` (5), `android_widget/` (2), `study_data/` (2). The
school-notification files were deliberately **not** moved:
`schoolNotificationDispatcher` is a Workmanager background entry point whose
callback handle, stored on the device, names its library; moving it would
break background checks of installed apps until they are opened again. A
comment at the entry point now says so.

**Documentation.** `docs/ARCHITECTURE.md` maps the layers, the middleware
parts, the feature folders and the rules that are easy to break.

**Remaining architectural issues:** see H.

## D. Code quality

**Bugs fixed (verified, with evidence).**

- *Target grade calculator, Legacy dialog for an earlier grade*: the two
  `TextEditingController`s were disposed right after `showDialog` returned,
  while the dialog was still animating out. The new widget test reproduced
  "A TextEditingController was used after being disposed" on the old code and
  passes now. The dialog owns its controllers, like the new-design sheet
  already did, and both share one parser instead of two copies.
- `setState` or a snackbar after an `await` without a `mounted` check:
  absence date pickers (2), study-phase editor, subject color picker,
  nickname dialogs (3), biometric lock error on the profile.
- `calendar_detail.dart` replaced an unattached `PageController` without
  disposing it.
- `CalendarSyncService._serialize`: an exception between replacing the queue
  tail and the `try` would have left the queue blocked forever; the
  completer is now completed in a `finally` that starts right away.

**Duplicates consolidated.**

| Copies | Now |
|---|---|
| Offline hint `l10n.text('grades.offlineMode', …formatTimeAgo…)`, 11 copies in 9 files | `AppLocalizations.offlineSince()` |
| "Last fetched HH:mm" `DateFormat.Hm(l10n.locale…)`, 6 copies | `AppLocalizations.formatHourMinute()` |
| UUID v4 generator in analytics and polls | `random_uuid.dart` (no app imports, so the polls privacy boundary holds) |
| Fixed `HH:mm` formatter, 3 copies | `formatClockTime()` in `util.dart` |
| Grade estimate with decimal comma, 3 grade containers | `formatGradeEstimate()` (same `toStringAsFixed` rounding) |
| Absences page: lesson-time collectors by date and by weekday (45 lines each) | one generic collector |
| Grade calculator average loop (Legacy and new design) | one `_averageHundredths()` |
| Earlier-grade validation (Legacy and new design) | one `_parseExistingGrade()` |
| Runtime-cache feature map, 2 copies | one constant |

Candidates deliberately **not** merged because the copies differ or the
risk outweighs the gain are listed in H.

**Dead code removed** (each checked with a repository-wide search,
including tests, tools, platform folders and dynamically built translation
keys): the `Donate` page (no route since `2d8a6116`), its 9 images and 12
texts per language; 21 further unused texts per language (e.g. of the iOS
mode removed in `6478a080`); a stale copy of the homework blacklist rule in
`days_container.dart`; `loadHomeworkSummaryHtml`, `SingleArgumentVoidCallback`,
`MapEntryToTuple`, `ProductAnalytics.identitySource`,
`AbsenceMonthlyHistory.spansMultipleYears`, `AnalyticsService.applyConsentChoice`
and its enum; a commented-out dark theme using APIs Flutter no longer has;
`toDate()` (equal to `UtcDateTime.stripTime()`); a local `AsyncCallback`
that shadowed Flutter's identical typedef; a redundant catch clause.

**No-op logging.** `logPerformanceEvent()` discarded its arguments (it only
called a privacy log that returns at once for that category), yet its 14
callers still built the data: every save of the app state UTF-8 encoded the
whole persisted JSON only to count bytes, and requests and message rendering
ran stopwatches for it. The function, its calls, `Wrapper._logDropped` and
the stopwatches are gone. Real diagnostics and analytics are untouched.

**Naming.** New names say what code does: `offlineSince`,
`formatHourMinute`, `formatClockTime`, `randomUuidV4`,
`onRequestTwoFactorCode`, `showTwoFactorCodeDialog`. Existing public names
were kept.

## E. Graphify analysis

| | Before (`cc469e70`) | After (`98253a8a`) |
|---|---|---|
| Nodes | 11,695 | 11,800 |
| Edges | 18,994 | 19,422 |
| Communities | 339 | 344 |
| Scope | `lib/`, `test/`, `CLAUDE.md` | same |

The counts grew slightly because the splits created more files (each file is
a node with its own import edges). That is expected and is not, by itself,
better or worse architecture.

File-level dependency analysis on `graph.json` (import edges, script in the
session):

- Service/domain files importing UI: **3 → 0** (`analytics_service`,
  `android_widget_snapshot`, `wrapper`). The remaining non-UI → UI edges are
  `main.dart` (the composition root) and the routing middleware, which is the
  established design and now also owns the two dialogs moved out of services.
- `middleware.dart` remains the most connected library (fan-out 79 → 81,
  because it now names the two dialogs); its size per file fell from 3,160 to
  at most 919 lines, which is what matters for reading and reviewing it.
- `lib/` files that nothing imports (outside `part`s): `ui/donations.dart`
  before, none after.
- Import cycles: none before, none after (Graphify report).

Graphify's top "god nodes" (`StatelessWidget`, `_`) are parser artifacts and
were not treated as findings. The update had to be scoped manually: a fresh
worktree has no extraction cache, so `graphify update .` first swept
`packages/` and the platform folders in (18,788 nodes). The committed graph
was rebuilt with a temporary, uncommitted `.graphifyignore`, and
`manifest.json` keeps its entries for the rest of the repository so that
later incremental updates elsewhere still skip those folders. Five curated
community labels whose communities changed were renamed by Graphify after
their hub files. Graphify derives the ids of symbols in Dart `part` files from
the absolute library path (416 such ids were already committed); they were
normalized from the worktree path to the repository path.

## F. Testing and verification

| Check | Result | Details |
|---|---|---|
| `dart format` | 30 files differ, all pre-existing (baseline 31) | Baseline: 31 files (15 lib, 16 test) already differed from `dart format`. Only touched files were formatted; the pure moves kept their original formatting. |
| `flutter analyze` | No issues found | Baseline: No issues found. Run after every group of changes. `analysis_options.yaml` was not changed; no lint was disabled. |
| `flutter test` | 3,532 passed, 12 skipped, 0 failed (final run) | Baseline: 3,531 passed, 12 skipped, 0 failed. Full suite run after each major group (7 full runs including baseline and final), targeted tests after each change. One run had an intermittent hang, see below. |
| Regression test | added | `test/ui/target_grade_calculator_test.dart`: fails on the old code, passes now |
| Additional checks | done | `dart analyze test tool`: 0 errors after the moves; repository-wide reference searches before each deletion; line-for-line verification scripts for both splits |

**Intermittent hang (not reproduced, cause not determined).** In one of the
seven full runs, the four cases of "hard logout completes exactly once" in
the existing `test/logout_persistence_test.dart` did not complete: the first
case started and never finished, with no timeout or assertion error. The
code under test was identical to the run before, which passed. The file then
passed 13 of 13 times on its own, and the immediate full rerun passed
completely. The test runs real-time async (storage retries of 200 ms, 1 s,
3 s) against global singletons shared within its isolate, which makes a
timing-dependent hang under full parallel load plausible, but this is an
assumption. Whether it also occurs on `main` is unknown. It is listed in H.

Failures introduced during the work and fixed: the local-data inventory test
reads source by path and needed the new file locations (twice); changing the
signature of `Wrapper.login` broke three test doubles, so the 2FA prompt
became a field instead. No pre-existing failures were found. Not tested:
platform builds (Android, iOS, Windows, web) and manual runs of the app; the
changes are Dart-only and covered by widget and unit tests, but a smoke test
of 2FA sign-in, the consent dialog and the biometric lock on a device is
advisable.

## G. Git information

- Repository: `https://github.com/Tobias-Bucci/digitales_register.git`
- Branch: `refactor/full-codebase-cleanup` (base `main` at `c3d4230b`)

| Commit | Message |
|---|---|
| `f15a7e9f` | refactor(middleware): split the middleware library into cohesive parts |
| `2a2ae8bd` | refactor(settings): move the settings sub-pages into parts |
| `a4d6ba5d` | fix(target-grade): keep the fields of the earlier-grade dialog alive while it closes |
| `a848fcd9` | fix: guard state updates after dialogs and keep the calendar sync queue moving |
| `7600dec3` | refactor(privacy): move the consent dialog out of the analytics service |
| `c0726a43` | refactor(grades): give the grade category its own domain file |
| `d6f72728` | refactor(network): let the sign-in ask for the 2FA code, not the wrapper |
| `4dc7c378` | refactor: keep widgets out of util, diagnostics and the app-lock controller |
| `2c2fbb18` | chore: remove dead code, the unreachable donation page and unused texts |
| `e9b30acb` | refactor(i18n): one helper each for the offline hint and the fetch time |
| `61c4fdbd` | refactor: share helpers that were copied between files |
| `7c907db3` | refactor: remove logPerformanceEvent, a logger that logs nothing |
| `af2a9986` | refactor: group grade, reminder, widget and study-data code into folders |
| `98253a8a` | docs: add an architecture map and guard the background entry point |
| `c0805eea` | chore(graphify): update the knowledge graph after the refactoring |

This report is the next commit. The branch is pushed to `origin/refactor/full-codebase-cleanup` as a new remote branch (no force push, no history rewrite); `main` is untouched.

Final working tree: clean apart from three generated Windows plugin files
that every `flutter pub get` rewrites with different line endings (no content
change); they are not committed.

## H. Remaining technical debt

High priority:

- **`SchoolNotificationService`** (`school_notification_service.dart`) is one
  class of about 1,700 lines (locks and history, lifecycle, permission,
  preferences, enrollment, scheduling, ingest, display, background sync). A
  split into a store, a background sync and a preferences controller is
  possible but its shared mutable state and static mutexes make it a design
  task for the owner. The file must not move (background entry point).
- **Copy-pasted loading state machine** in `class_register_page.dart`,
  `homework_summary_page.dart` and `course_materials_page.dart` (about 300
  lines each share fields, `_initialize`, `_refresh`, `_applySnapshot`). The
  copies differ in error handling, so a shared loader needs careful tests
  first.

Medium priority:

- `test/logout_persistence_test.dart` hung once in seven full runs (section
  F); worth investigating with repeated full runs on `main` and on this branch.
- `wrapper.dart`: `send` and `sendBytes` are about 80 % alike; the HTML
  config parser could move to its own file; the wrapper still reports offline
  state through the global `actions` of `main.dart`.
- `android_widget/android_widget_service.dart` pops to the dashboard through
  the navigator keys (routing glue outside the routing middleware).
- `GradesChart` creates a `ValueNotifier` in a `StatelessWidget`, so a rebuild
  loses the selection; fixing it changes behavior and needs a decision.
- About 34 calls of `privacyLog('technical_operation')` are no-ops by design
  (`privacy_log.dart`); removing them would leave empty catch blocks that need
  individual review.
- Five hand-written serial queues with different error semantics (analytics,
  widget snapshot, state persistence, diagnostics, calendar sync).

Low priority:

- Legacy and new message badges share their rule only together with a
  separate Legacy branch; polls and server notifications repeat small
  timestamp/UUID wire helpers inside folders guarded by privacy-boundary
  tests; repeated reduced-motion duration helpers.
- `DiagnosticsService.listenToWorker` has no callers (kept: it may serve
  isolates); `AuthTokens.space6` is unused (kept as a design token).
- About 25 translation keys look unused but were kept because keys are also
  built at run time (`'$translationPrefix.lastFetched'`), which a text search
  cannot rule out.
- `dart format` differs on 31 files that were unformatted before this work;
  formatting them is a separate, purely cosmetic change.

None of these needs approval to investigate; the school-notification split
and any change of the chart behavior need the owner's decision.

## I. Changed files

Most significant:

- `lib/middleware/middleware.dart` and new parts `analytics.dart`,
  `course_materials.dart`, `downloads.dart`, `page_payloads.dart`,
  `persistence.dart`, `runtime_cache.dart`, `study_data.dart`: the god library
  split.
- `lib/ui/settings_page_widget.dart` and new `lib/ui/settings/*.dart`: the
  settings sub-pages.
- `lib/analytics_service.dart` → new `lib/ui/privacy_consent_dialog.dart`;
  `lib/wrapper.dart` + `lib/middleware/login.dart` → new
  `lib/ui/two_factor_dialog.dart`; `lib/biometric_app_lock.dart` → new
  `lib/ui/biometric_app_lock_overlay.dart`; `lib/ui/grade_colors.dart` → new
  `lib/grades/grade_category.dart`: layering.
- `lib/ui/target_grade_calculator.dart` (+ `_new`), `lib/ui/profile.dart`,
  `lib/ui/absences_page.dart`, `lib/ui/exam_calendar_page.dart`,
  `lib/ui/calendar_detail.dart`, `lib/calendar_sync_service.dart`,
  settings parts: bug fixes.
- `lib/i18n/app_localizations.dart`, `lib/util.dart`, new
  `lib/random_uuid.dart`, absences, grade calculator and grade containers:
  shared helpers.
- Renamed into `lib/grades/`, `lib/reminders/`, `lib/android_widget/`,
  `lib/study_data/`: 14 files plus the new `grade_category.dart`.
- Deleted: `lib/ui/donations.dart`, 9 images in `assets/`; edited:
  `assets/locales/{de,en,it,lld}.json` (33 unused keys each).
- Tests: `test/local_data_inventory_test.dart` (paths),
  `test/ui/target_grade_calculator_test.dart` (regression test), four privacy
  tests and two lifecycle tests (new function names and imports).
- Docs: new `docs/ARCHITECTURE.md`, `docs/STORE_PRIVACY_CHECKLIST.md` (no
  donation links any more), this report.
- `graphify-out/`: updated graph, report, HTML, labels and manifest.
