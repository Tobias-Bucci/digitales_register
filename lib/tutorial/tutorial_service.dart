import 'dart:async';

import 'package:dr/analytics_service.dart';
import 'package:dr/app_language_controller.dart';
import 'package:dr/main.dart';
import 'package:dr/tutorial/intro_tour.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Offers the intro once after the first sign-in and replays it on request.
class TutorialService extends ChangeNotifier {
  static const seenKey = 'tutorial.v3.seen';
  // Anyone who saw or dismissed the old spotlight tour is not offered the
  // new intro automatically; it stays available in the settings.
  static const _legacyPrefix = 'tutorial.v2.';

  bool _active = false;
  bool _checkingOffer = false;
  bool _offerScheduled = false;

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
      if (!await shouldOffer() || !context.mounted) return;
      await start(context);
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
      // again.
      await prefs.setBool(seenKey, true);
      if (!context.mounted) return;
      unawaited(AnalyticsService.product
          .event('onboarding_step', {'step_id': 'welcome', 'action': 'shown'}));
      final finished = await Navigator.of(context, rootNavigator: true).push(
        IntroTour.route(
          language: appLanguageController.language,
          onLanguageSelected: (language) =>
              actions.settingsActions.setLanguage(language.code),
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
}

final tutorialService = TutorialService();
