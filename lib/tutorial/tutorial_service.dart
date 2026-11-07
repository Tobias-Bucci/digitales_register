import 'dart:async';

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/analytics_service.dart';
import 'package:dr/app_language_controller.dart';
import 'package:dr/app_state.dart';
import 'package:dr/main.dart';
import 'package:dr/tutorial/design_choice.dart';
import 'package:dr/tutorial/intro_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Offers the intro once after the first sign-in and replays it on request.
///
/// It also asks once which design to use (#108): new installations at the
/// end of the intro, people who used an earlier version on a screen of its
/// own. The answer is remembered for the installation, not for an account or
/// a version, so no later update asks again.
class TutorialService extends ChangeNotifier {
  static const seenKey = 'tutorial.v3.seen';

  /// Set once the user has chosen between the new and the legacy design. The
  /// design itself is `legacyDesign` in the settings.
  static const designChoiceKey = 'designChoiceMade';
  // Anyone who saw or dismissed the old spotlight tour is not offered the
  // new intro automatically; it stays available in the settings.
  static const _legacyPrefix = 'tutorial.v2.';

  bool _active = false;
  bool _checkingOffer = false;
  bool _offerScheduled = false;

  /// Closing the question without an answer asks again on the next start,
  /// not every time the dashboard comes back.
  bool _designAskedThisRun = false;

  bool get active => _active;

  Future<bool> shouldOffer() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyKeys =
        prefs.getKeys().where((key) => key.startsWith(_legacyPrefix)).toList();
    if (legacyKeys.isNotEmpty) {
      for (final key in legacyKeys) {
        await prefs.remove(key);
      }
      await prefs.setBool(seenKey, true);
      return false;
    }
    return prefs.getBool(seenKey) != true;
  }

  /// Whether the user has not chosen a design yet.
  Future<bool> designChoicePending() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(designChoiceKey) != true;
  }

  /// Ask for a frame explicitly; an idle dashboard may not paint again until
  /// the user interacts with it.
  void scheduleOffer(BuildContext context, {bool Function()? isCurrent}) {
    if (_offerScheduled || _checkingOffer || _active) return;
    _offerScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _offerScheduled = false;
      if (!context.mounted || !(isCurrent?.call() ?? true)) return;
      unawaited(maybeOffer(context));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> maybeOffer(BuildContext context) async {
    if (_checkingOffer || _active) return;
    _checkingOffer = true;
    try {
      if (await shouldOffer()) {
        if (!context.mounted) return;
        await start(context);
      } else if (!_designAskedThisRun && await designChoicePending()) {
        if (!context.mounted) return;
        await offerDesignChoice(context);
      }
    } finally {
      _checkingOffer = false;
    }
  }

  /// Shows the intro. Completes once it is finished or skipped.
  Future<void> start(BuildContext context) async {
    if (_active) return;
    _active = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      // Saved up front so an interrupted intro is never forced on the user
      // again. The design is not: without an answer it is asked on its own.
      await prefs.setBool(seenKey, true);
      final designPending = prefs.getBool(designChoiceKey) != true;
      _designAskedThisRun = true;
      if (!context.mounted) return;
      final store = _storeOf(context);
      unawaited(AnalyticsService.product
          .event('onboarding_step', {'step_id': 'welcome', 'action': 'shown'}));
      final finished = await Navigator.of(context, rootNavigator: true).push(
        IntroTour.route(
          language: appLanguageController.language,
          onLanguageSelected: (language) =>
              actions.settingsActions.setLanguage(language.code),
          legacyDesign: store?.state.settingsState.legacyDesign ?? false,
          designChoicePending: designPending,
          onDesignChosen: (legacy) => unawaited(_chooseDesign(store, legacy)),
        ),
      );
      unawaited(AnalyticsService.product.event('onboarding_step', {
        'step_id': 'complete',
        'action': finished == true ? 'completed' : 'skipped',
      }));
    } finally {
      _active = false;
      notifyListeners();
    }
  }

  /// Asks for the design on its own screen, with the design in use selected.
  Future<void> offerDesignChoice(BuildContext context) async {
    if (_active) return;
    _active = true;
    _designAskedThisRun = true;
    notifyListeners();
    try {
      final store = _storeOf(context);
      final legacy = await Navigator.of(context, rootNavigator: true).push(
        DesignChoiceScreen.route(
          legacyDesign: store?.state.settingsState.legacyDesign ?? false,
        ),
      );
      if (legacy != null) await _chooseDesign(store, legacy);
    } finally {
      _active = false;
      notifyListeners();
    }
  }

  /// The design first, then the marker: stopped in between, the question
  /// comes again and nothing is lost.
  Future<void> _chooseDesign(
    Store<AppState, AppStateBuilder, AppActions>? store,
    bool legacy,
  ) async {
    if (store != null && store.state.settingsState.legacyDesign != legacy) {
      await store.actions.settingsActions.legacyDesign(legacy);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(designChoiceKey, true);
  }

  static Store<AppState, AppStateBuilder, AppActions>? _storeOf(
      BuildContext context) {
    final store = context.getInheritedWidgetOfExactType<ReduxProvider>()?.store;
    return store is Store<AppState, AppStateBuilder, AppActions> ? store : null;
  }
}

final tutorialService = TutorialService();
