import 'dart:async';

import 'package:dr/analytics_service.dart';
import 'package:dr/app_language_controller.dart';
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/tutorial/tutorial_overlay.dart';
import 'package:dr/ui/target_grade_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TutorialChapter { dashboard, grades }

class TutorialStep {
  const TutorialStep(this.chapter, this.key,
      {required this.target,
      this.openedTarget,
      this.completionTarget,
      this.requiresAction = false});
  final TutorialChapter chapter;
  final String key;
  final String target;
  final String? openedTarget;
  final String? completionTarget;
  final bool requiresAction;
}

class TutorialTargetRegistry {
  final Map<String, List<BuildContext>> _contexts = {};
  void register(String id, BuildContext context) {
    final entries = _contexts.putIfAbsent(id, () => []);
    if (!entries.contains(context)) entries.add(context);
  }

  void remove(String id, BuildContext context) {
    _contexts[id]?.remove(context);
  }

  BuildContext? _contextFor(String? id) {
    final candidates = _contexts[id] ?? [];
    BuildContext? fallback;
    for (final context in candidates) {
      if (!context.mounted) continue;
      if (ModalRoute.of(context)?.isCurrent == false) continue;
      var hidden = false;
      context.visitAncestorElements((element) {
        final widget = element.widget;
        if ((widget is Offstage && widget.offstage) ||
            (widget is Opacity && widget.opacity == 0)) {
          hidden = true;
        }
        return !hidden;
      });
      if (hidden) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox ||
          !box.attached ||
          !box.hasSize ||
          box.size.isEmpty) {
        continue;
      }
      fallback ??= context;
      final rect = _visibleBounds(box);
      if (rect == null) continue;
      if (rect.overlaps(Offset.zero & MediaQuery.sizeOf(context))) {
        return context;
      }
    }
    return fallback;
  }

  Rect? rectFor(String? id) {
    final context = _contextFor(id);
    if (context == null || !context.mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (box.size.isEmpty) return null;
    return _visibleBounds(box);
  }

  Rect? _visibleBounds(RenderBox box) {
    var rect = _bounds(box);
    if (rect == null) return null;
    RenderObject? ancestor = box.parent;
    while (ancestor != null) {
      if (ancestor is RenderBox &&
          (ancestor is RenderAbstractViewport ||
              ancestor is RenderClipRect ||
              ancestor is RenderClipRRect)) {
        final clip = _bounds(ancestor);
        if (clip == null) return null;
        rect = rect!.intersect(clip);
      }
      ancestor = ancestor.parent;
    }
    return rect!.isEmpty ? null : rect;
  }

  Rect? _bounds(RenderBox box) {
    // Route transitions use fractional transforms which need their ancestors'
    // layout. During the first build these may not have a size yet.
    RenderObject? ancestor = box;
    while (ancestor != null) {
      if (ancestor is RenderBox && !ancestor.hasSize) return null;
      ancestor = ancestor.parent;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Rect? boundsFor(BuildContext context) {
    final box = context.findRenderObject();
    return box is RenderBox && box.attached ? _bounds(box) : null;
  }

  Route<dynamic>? routeFor(String? id) {
    final context = _contextFor(id);
    return context == null ? null : ModalRoute.of(context);
  }

  Future<void> reveal(String? id) async {
    final context = _contextFor(id);
    if (context == null) return;
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      alignment: .45,
    );
  }
}

final tutorialTargets = TutorialTargetRegistry();

/// A short guided path through the real controls, with explicit confirmations.
const tutorialSteps = <TutorialStep>[
  TutorialStep(TutorialChapter.dashboard, 'welcome', target: 'dashboard-page'),
  TutorialStep(TutorialChapter.dashboard, 'deadlines',
      target: 'dashboard-deadline',
      openedTarget: 'deadline-dialog',
      requiresAction: true),
  TutorialStep(TutorialChapter.dashboard, 'settings',
      target: 'navigation-menu',
      openedTarget: 'navigation-settings',
      completionTarget: 'settings-page',
      requiresAction: true),
  TutorialStep(TutorialChapter.dashboard, 'tutorialHelp',
      target: 'settings-tutorial',
      completionTarget: 'tutorial-page',
      requiresAction: true),
  TutorialStep(TutorialChapter.grades, 'grades',
      target: 'navigation-menu',
      openedTarget: 'navigation-grades',
      completionTarget: 'grades-page',
      requiresAction: true),
  TutorialStep(TutorialChapter.grades, 'calculator',
      target: 'grades-calculator',
      openedTarget: 'calculator-target',
      completionTarget: 'target-calculator-form',
      requiresAction: true),
  TutorialStep(TutorialChapter.grades, 'calculatorTarget',
      target: 'target-calculator-calculate',
      openedTarget: 'target-calculator-result',
      requiresAction: true),
];

/// Makes widget callbacks use the same service as the hosting tutorial (also in tests).
class TutorialScope extends InheritedNotifier<TutorialService> {
  const TutorialScope(
      {super.key, required TutorialService service, required super.child})
      : super(notifier: service);
}

class TutorialService extends ChangeNotifier {
  static TutorialService of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TutorialScope>()?.notifier ??
      tutorialService;
  // Retain v2 offer/completion keys so updates never re-offer the old tour.
  static const _offeredKey = 'tutorial.v2.offered';
  static const _completedPrefix = 'tutorial.v2.completed.';
  OverlayEntry? _entry;
  AppLocalizations? _l10n;
  List<TutorialStep> _active = const [];
  int _index = 0;
  bool _checkingOffer = false;
  bool _starting = false;
  bool _advancing = false;
  Timer? _tracking;
  Route<dynamic>? _rootRoute;
  Route<dynamic>? _nestedRoute;
  Rect? _lastRect;
  String? _lastTarget;
  bool suspended = false;
  final Set<String> _completedActions = {};

  bool get active => _entry != null;
  TutorialStep get step => _active[_index];
  int get index => _index;
  int get length => _active.length;
  bool get canContinue =>
      active &&
      !_advancing &&
      (!step.requiresAction || _completedActions.contains(step.key));
  bool get canGoBack => active && !_advancing;
  String? get highlightTarget {
    if (!active) return null;
    for (final target in [step.completionTarget, step.openedTarget]) {
      if (target != null && tutorialTargets.routeFor(target) != null) {
        return target;
      }
    }
    return suspended ? null : step.target;
  }

  void completeAction(String key) {
    if (!active || step.key != key || !step.requiresAction) return;
    if (_completedActions.add(key)) notifyListeners();
  }

  String text(String suffix) => _l10n?.text('tutorial.$suffix') ?? suffix;
  String stepTitle() => text('step.${step.key}.title');
  String stepBody() => text('step.${step.key}.body');

  Route<dynamic>? _top(GlobalKey<NavigatorState>? key) {
    Route<dynamic>? result;
    key?.currentState?.popUntil((route) {
      result = route;
      return true;
    });
    return result;
  }

  void _captureRoutes() {
    _rootRoute = _top(navigatorKey);
    _nestedRoute = _top(nestedNavKey);
    suspended = false;
    _lastRect = null;
    _lastTarget = null;
  }

  void _track() {
    if (!active || _advancing) return;
    final covered =
        _top(navigatorKey) != _rootRoute || _top(nestedNavKey) != _nestedRoute;
    if (step.completionTarget != null &&
        tutorialTargets.routeFor(step.completionTarget) != null) {
      completeAction(step.key);
    }
    final target = highlightTarget;
    final rect = tutorialTargets.rectFor(target);
    final newTarget = target != _lastTarget &&
        target != null &&
        tutorialTargets.routeFor(target) != null;
    if (covered != suspended || rect != _lastRect || newTarget) {
      suspended = covered;
      _lastRect = rect;
      notifyListeners();
      if (newTarget) {
        _lastTarget = target;
        unawaited(tutorialTargets.reveal(target));
      }
    }
  }

  Future<bool> isChapterCompleted(TutorialChapter chapter) async =>
      (await SharedPreferences.getInstance())
          .getBool('$_completedPrefix${chapter.name}') ??
      false;

  /// Old numeric progress referred to a different sequence and was never
  /// resumed. Discard it; manual replay always starts at the beginning.
  Future<bool> shouldOffer() async {
    final prefs = await SharedPreferences.getInstance();
    final hasHistory = prefs.getBool(_offeredKey) == true ||
        prefs.containsKey('tutorial.v2.progress') ||
        prefs.getKeys().any((key) =>
            key.startsWith(_completedPrefix) && prefs.getBool(key) == true);
    await prefs.remove('tutorial.v2.progress');
    if (hasHistory) {
      await prefs.setBool(_offeredKey, true);
    }
    return !hasHistory;
  }

  Future<void> maybeOffer(BuildContext context) async {
    // Dashboard fragments in widget tests do not represent a real login.
    if (WidgetsBinding.instance.runtimeType
        .toString()
        .contains('TestWidgetsFlutterBinding')) {
      return;
    }
    if (_checkingOffer || active || _starting) return;
    _checkingOffer = true;
    try {
      if (!await shouldOffer() || !context.mounted) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_offeredKey, true);
      if (!context.mounted) return;
      final begin = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.explore_outlined),
          title: Text(dialogContext.l10n.text('tutorial.offer.title')),
          content: Text(dialogContext.l10n.text('tutorial.offer.body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogContext.l10n.text('tutorial.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogContext.l10n.text('tutorial.begin')),
            ),
          ],
        ),
      );
      if (begin == true && context.mounted) await startAll(context);
    } finally {
      _checkingOffer = false;
    }
  }

  Future<void> startAll(BuildContext context, {AppLanguage? language}) =>
      _start(context, tutorialSteps, language: language);

  Future<void> startChapter(BuildContext context, TutorialChapter chapter) =>
      _start(
          context, tutorialSteps.where((s) => s.chapter == chapter).toList());

  Future<void> _start(BuildContext context, List<TutorialStep> steps,
      {AppLanguage? language}) async {
    if (_starting || steps.isEmpty) return;
    _starting = true;
    try {
      await cancel();
      if (!context.mounted) return;
      await shouldOffer();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_offeredKey, true);
      if (!context.mounted) return;
      final selected = language ?? await _chooseLanguage(context);
      if (selected == null || !context.mounted) return;
      await actions.settingsActions.setLanguage(selected.code);
      _l10n = await AppLocalizations.load(selected.locale);
      if (!context.mounted) return;
      _active = steps;
      _completedActions.clear();
      _index = 0;
      await _showPage(step);
      final overlay = navigatorKey?.currentState?.overlay;
      if (overlay == null) {
        _active = const [];
        return;
      }
      _entry = OverlayEntry(builder: (_) => TutorialOverlay(service: this));
      overlay.insert(_entry!);
      _captureRoutes();
      notifyListeners();
      final entry = _entry;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_entry != entry) return;
        _tracking?.cancel();
        _tracking =
            Timer.periodic(const Duration(milliseconds: 80), (_) => _track());
      });
      unawaited(AnalyticsService.product
          .event('onboarding_step', {'step_id': 'welcome', 'action': 'shown'}));
    } finally {
      _starting = false;
    }
  }

  Future<void> next() async {
    if (!active || !canContinue) return;
    if (_index + 1 == length) {
      await _finish();
    } else {
      await _moveTo(_index + 1);
    }
  }

  Future<void> previous() async {
    if (!active || _advancing || _index == 0) return;
    await _moveTo(_index - 1);
  }

  Future<void> back() async {
    if (!active || _advancing) return;
    if (_index == 0) {
      await cancel();
    } else {
      await previous();
    }
  }

  Future<void> _moveTo(int index) async {
    _advancing = true;
    notifyListeners();
    try {
      final previous = step;
      _index = index;
      if (previous.key != step.key) {
        await _showPage(step);
      }
      if (!active) return;
      _captureRoutes();
    } finally {
      _advancing = false;
      notifyListeners();
    }
  }

  Future<void> _finish() async {
    _advancing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final chapter in _active.map((s) => s.chapter).toSet()) {
        await prefs.setBool('$_completedPrefix${chapter.name}', true);
      }
      unawaited(AnalyticsService.product.event(
          'onboarding_step', {'step_id': 'complete', 'action': 'completed'}));
      await cancel();
    } finally {
      _advancing = false;
    }
  }

  Future<void> cancel() async {
    _tracking?.cancel();
    _tracking = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    _active = const [];
    _index = 0;
    suspended = false;
    notifyListeners();
  }

  Future<AppLanguage?> _chooseLanguage(BuildContext context) =>
      showDialog<AppLanguage>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.l10n.text('tutorial.language.title')),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(dialogContext.l10n.text('tutorial.language.body')),
            for (final language in AppLanguage.values)
              ListTile(
                leading: Icon(language == appLanguageController.language
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(switch (language) {
                  AppLanguage.de => 'Deutsch',
                  AppLanguage.it => 'Italiano',
                  AppLanguage.en => 'English',
                  AppLanguage.lld => 'Ladin',
                }),
                onTap: () => Navigator.pop(dialogContext, language),
              ),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(dialogContext.l10n.text('tutorial.cancel')))
          ],
        ),
      );

  Future<void> _showPage(TutorialStep value) async {
    // Keep the view reached by the user's click. Rebuild it only on replay/back.
    final destination = switch (value.key) {
      'tutorialHelp' => 'settings-page',
      'calculator' => 'grades-page',
      'calculatorTarget' => 'target-calculator-form',
      _ => null,
    };
    if (destination != null &&
        tutorialTargets.routeFor(destination) != null &&
        (destination == 'target-calculator-form'
            ? tutorialTargets.routeFor(destination) == _top(navigatorKey)
            : _top(navigatorKey)?.isFirst == true)) {
      return;
    }
    navigatorKey?.currentState?.popUntil((route) => route.isFirst);
    final scaffold = scaffoldKey?.currentState;
    switch (value.key) {
      case 'welcome':
      case 'deadlines':
      case 'settings':
      case 'grades':
        scaffold?.goHome();
      case 'tutorialHelp':
        scaffold?.selectContentWidget(SettingsPageContainer(), Pages.settings);
      case 'calculator':
        scaffold?.selectContentWidget(
            const GradesPageContainer(), Pages.grades);
      case 'calculatorTarget':
        unawaited(navigatorKey?.currentState?.push(MaterialPageRoute<void>(
          builder: (_) => const TargetGradeCalculator(tutorialExample: true),
        )));
    }
  }

  @override
  void dispose() {
    _tracking?.cancel();
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    super.dispose();
  }
}

final tutorialService = TutorialService();
