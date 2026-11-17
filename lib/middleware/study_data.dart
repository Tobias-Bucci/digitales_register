// Copyright (C) 2021 Michael Debertol
// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

part of 'middleware.dart';

// Learning notes (exam progress, notes, files) of the signed-in account,
// including the offer to adopt notes saved before accounts had their own.

/// The account whose learning notes are in the settings of the store, or null
/// while they are not (not loaded yet, or they could not be read). Notes are
/// only saved for this account: a failed read must never be followed by a
/// write that replaces what could not be read.
AccountScope? _studyDataScope;

AccountScope _studyScopeOf(String? username) =>
    AccountScope(wrapper.url, username);

/// Puts the learning notes of the account that just signed in into the
/// settings of the store. Whoever signed in before left none behind.
Future<void> _mountStudyData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  _Session session,
  String? username, {
  bool quiet = false,
}) async {
  final scope = _studyScopeOf(username);
  _studyDataScope = null;
  var unreadable = false;
  // The notes older versions kept for all accounts are put aside before any
  // account reads its own. A read that fails postpones this to the next start.
  try {
    await studyDataMigration.ensureQuarantined();
    legacyStudyDataRevision.value++;
  } on StudyDataUnreadable catch (error, stack) {
    diagnostics.report(error, stack, DiagnosticError.storage);
    unreadable = true;
  } catch (error, stack) {
    diagnostics.report(error, stack, DiagnosticError.storage);
  }
  session.ensureCurrent();
  StudyData data;
  try {
    data = await studyDataService.load(scope);
  } on StudyDataUnreadable catch (error, stack) {
    session.ensureCurrent();
    diagnostics.report(error, stack, DiagnosticError.storage);
    if (!quiet) showSnackBar(tr('error.savedDataUnreadable'));
    return;
  }
  session.ensureCurrent();
  if (unreadable && !quiet) showSnackBar(tr('error.savedDataUnreadable'));
  await api.actions.mountAppState(
    api.state.rebuild((b) => b
      ..settingsState.replace(
        data.applyTo(api.state.settingsState),
      )),
  );
  _studyDataScope = scope;
  WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_offerLegacyStudyData(api, session)));
}

const _legacyStudyPromptedKey = 'studyDataLegacyPromptedV1';

/// Once, after the first sign-in that finds older learning notes without an
/// account, asks what to do with them. Closing the question means later.
Future<void> _offerLegacyStudyData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  _Session session,
) async {
  try {
    if (!session.isCurrent || wrapper.demoMode || session.scope.user == null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_legacyStudyPromptedKey) ?? false) return;
    final summary = await studyDataMigration.summary();
    if (summary == null) return;
    session.ensureCurrent();
    await prefs.setBool(_legacyStudyPromptedKey, true);
    await showLegacyStudyDataDialog(api.actions, summary);
  } on StaleSessionException {
    // The account was left before the question was asked.
  } on StudyDataUnreadable {
    // Asked at the next start.
  } catch (error, stack) {
    diagnostics.report(error, stack, DiagnosticError.storage);
  }
}

Map<String, String> _legacyStudyArgs({int? exams, int? notes, int? files}) {
  final context = navigatorKey?.currentContext;
  if (context == null) return const {};
  return AppLocalizations.of(context)
      .legacyStudyCounts(exams: exams, notes: notes, files: files);
}

Map<String, String> _legacyStudySummaryArgs(LegacyStudySummary summary) =>
    _legacyStudyArgs(
        exams: summary.exams, notes: summary.notes, files: summary.files);

enum _LegacyStudyChoice { assign, later, discard }

/// Asks what to do with the older learning notes: numbers only, never their
/// content. Closing the dialog keeps them (later); discarding needs a second
/// confirmation.
Future<void> showLegacyStudyDataDialog(
  AppActions actions,
  LegacyStudySummary summary,
) async {
  final navigator = navigatorKey?.currentState;
  final context = navigatorKey?.currentContext;
  if (navigator == null || context == null) return;
  if (newDesignChosen(context)) {
    final choice = await navigator.push<_LegacyStudyChoice>(
      glassSheetRoute(
        context: context,
        builder: (context) => NewDesignTheme(
          child: _LegacyStudyDataSheet(summary: summary),
        ),
      ),
    );
    await _actOnLegacyStudyChoice(actions, summary, choice);
    return;
  }
  final choice = await navigator.push<_LegacyStudyChoice>(
    DialogRoute(
      context: context,
      builder: (context) => InfoDialog(
        title: Text(tr('studyData.legacy.title')),
        content: Text(tr('studyData.legacy.body',
            args: _legacyStudySummaryArgs(summary))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _LegacyStudyChoice.discard),
            child: Text(tr('studyData.legacy.discard')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _LegacyStudyChoice.assign),
            child: Text(tr('studyData.legacy.assign')),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, _LegacyStudyChoice.later),
            child: Text(tr('studyData.legacy.later')),
          ),
        ],
      ),
    ),
  );
  await _actOnLegacyStudyChoice(actions, summary, choice);
}

Future<void> _actOnLegacyStudyChoice(
  AppActions actions,
  LegacyStudySummary summary,
  _LegacyStudyChoice? choice,
) async {
  switch (choice) {
    case _LegacyStudyChoice.assign:
      await actions.assignLegacyStudyData();
    case _LegacyStudyChoice.discard:
      if (await _confirmDiscardLegacyStudyData(summary) == true) {
        await actions.discardLegacyStudyData();
      }
    case _LegacyStudyChoice.later:
    case null:
      break;
  }
}

/// The question of [showLegacyStudyDataDialog] in the new design, as a glass
/// sheet with the same texts and answers.
class _LegacyStudyDataSheet extends StatelessWidget {
  const _LegacyStudyDataSheet({required this.summary});

  final LegacyStudySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassPanel(
      title: tr('studyData.legacy.title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('studyData.legacy.body', args: _legacyStudySummaryArgs(summary)),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SettingsSheetActions(
            children: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _LegacyStudyChoice.discard),
                child: Text(tr('studyData.legacy.discard')),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _LegacyStudyChoice.assign),
                child: Text(tr('studyData.legacy.assign')),
              ),
              FilledButton(
                autofocus: true,
                onPressed: () =>
                    Navigator.pop(context, _LegacyStudyChoice.later),
                child: Text(tr('studyData.legacy.later')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<bool?> _confirmDiscardLegacyStudyData(LegacyStudySummary summary) {
  final context = navigatorKey?.currentContext;
  if (context == null) return Future.value(false);
  final newDesign = newDesignChosen(context);
  return navigatorKey!.currentState!.push<bool>(
    DialogRoute(
      context: context,
      // A short yes or no stays a dialog, as in the settings; in the new
      // design it has the rim of the glass.
      builder: (context) {
        final dialog = InfoDialog(
          title: Text(tr('studyData.legacy.discardConfirm.title')),
          content: Text(tr('studyData.legacy.discardConfirm.body',
              args: _legacyStudySummaryArgs(summary))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('studyData.legacy.discardConfirm.confirm')),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('common.cancel')),
            ),
          ],
        );
        return newDesign ? NewDesignTheme(child: dialog) : dialog;
      },
    ),
  );
}

/// Gives the older learning notes to the account that is signed in.
Future<void> _assignLegacyStudyData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  final session = _Session.capture();
  final scope = _studyScopeOf(api.state.loginState.username);
  // The demo account has no notes of its own to receive them, and an account
  // whose notes were not read must not be written to.
  if (!api.state.loginState.loggedIn ||
      scope.user == null ||
      wrapper.demoMode ||
      _studyDataScope != scope) {
    showSnackBar(tr('studyData.legacy.assignFailed'));
    return;
  }
  try {
    final outcome = await statePersistenceService.runExclusive(() async {
      session.ensureCurrent();
      final result = await studyDataMigration.assign(
        scope,
        current: StudyData.fromSettings(api.state.settingsState),
      );
      session.ensureCurrent();
      // With what was typed in the meantime, which replaces nothing.
      final merged = StudyData.fromSettings(api.state.settingsState)
          .withMissingFrom(result.moved);
      await api.actions.mountAppState(
        api.state.rebuild((b) =>
            b..settingsState.replace(merged.applyTo(api.state.settingsState))),
      );
      return result;
    });
    legacyStudyDataRevision.value++;
    if (outcome.moved.isEmpty && outcome.remaining.isEmpty) return;
    showSnackBar(outcome.remaining.isEmpty
        ? tr('studyData.legacy.assigned',
            args: _legacyStudyArgs(
              notes: outcome.moved.noteCount,
              files: outcome.moved.fileCount,
            ))
        : tr('studyData.legacy.assignedPartly',
            args: _legacyStudyArgs(
              notes: outcome.moved.noteCount,
              files: outcome.moved.fileCount,
              exams: outcome.remaining.keys.length,
            )));
  } on StaleSessionException {
    rethrow;
  } catch (error, stack) {
    diagnostics.report(error, stack, DiagnosticError.storage);
    legacyStudyDataRevision.value++;
    showSnackBar(tr('studyData.legacy.assignFailed'));
  }
}

/// Deletes the older learning notes for good. Asked twice before.
Future<void> _discardLegacyStudyData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  try {
    await statePersistenceService.runExclusive(studyDataMigration.discard);
    legacyStudyDataRevision.value++;
    showSnackBar(tr('studyData.legacy.discarded'));
  } catch (error, stack) {
    diagnostics.report(error, stack, DiagnosticError.storage);
    legacyStudyDataRevision.value++;
    showSnackBar(tr('studyData.legacy.discardFailed'));
  }
}

/// Saves the learning notes of the signed-in account after they changed.
Future<void> _persistStudyData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
) async {
  final state = api.state;
  if (deletedData || !state.loginState.loggedIn) return;
  final scope = _studyScopeOf(state.loginState.username);
  if (_studyDataScope != scope) return;
  final requested = StudyData.fromSettings(state.settingsState);
  try {
    // Behind every earlier write and deletion, in the order requested. What
    // is written is what the account has by then, so a save that waited
    // behind a move of the older notes cannot write them away again.
    await statePersistenceService.runExclusive(() {
      final stillSignedIn = !deletedData &&
          api.state.loginState.loggedIn &&
          _studyScopeOf(api.state.loginState.username) == scope &&
          _studyDataScope == scope;
      return studyDataService.save(
        scope,
        stillSignedIn
            ? StudyData.fromSettings(api.state.settingsState)
            : requested,
      );
    });
  } catch (error, stack) {
    diagnostics.report(error, stack, DiagnosticError.storage);
  }
}

bool _studyDataChanged(SettingsState before, SettingsState after) =>
    before.assessmentStudyProgress != after.assessmentStudyProgress ||
    before.assessmentStudyNotes != after.assessmentStudyNotes ||
    before.assessmentStudyAttachments != after.assessmentStudyAttachments ||
    before.assessmentStudyPhases != after.assessmentStudyPhases;
