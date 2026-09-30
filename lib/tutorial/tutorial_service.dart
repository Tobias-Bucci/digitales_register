import 'dart:async';
import 'package:dr/analytics_service.dart';

import 'package:dr/app_language_controller.dart';
import 'package:dr/container/exam_calendar_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/tutorial/tutorial_overlay.dart';
import 'package:dr/ui/class_register_page.dart';
import 'package:dr/ui/course_materials_page.dart';
import 'package:dr/ui/homework_summary_page.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TutorialChapter {
  dashboard,
  grades,
  absences,
  calendar,
  exams,
  other,
}

class TutorialStep {
  const TutorialStep(this.chapter, this.key,
      {this.target, this.openedTarget, this.requiresAction = false});
  final TutorialChapter chapter;
  final String key;
  final String? target;
  final String? openedTarget;
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

const _steps = <TutorialStep>[
  TutorialStep(TutorialChapter.dashboard, 'welcome', target: 'dashboard-page'),
  TutorialStep(TutorialChapter.dashboard, 'holidays',
      target: 'dashboard-holidays'),
  TutorialStep(TutorialChapter.dashboard, 'deadlines',
      target: 'dashboard-deadline', requiresAction: true),
  TutorialStep(TutorialChapter.dashboard, 'filter',
      target: 'dashboard-filter', requiresAction: true),
  TutorialStep(TutorialChapter.dashboard, 'past',
      target: 'dashboard-past', requiresAction: true),
  TutorialStep(TutorialChapter.dashboard, 'reminders',
      target: 'dashboard-reminder', requiresAction: true),
  TutorialStep(TutorialChapter.dashboard, 'deleteReminder',
      target: 'dashboard-created-reminder', requiresAction: true),
  TutorialStep(TutorialChapter.dashboard, 'assessmentShortcuts',
      target: 'dashboard-reminder', requiresAction: true),
  TutorialStep(TutorialChapter.dashboard, 'deleteAssessment',
      target: 'dashboard-created-reminder', requiresAction: true),
  TutorialStep(TutorialChapter.grades, 'semester', target: 'grades-semester'),
  TutorialStep(TutorialChapter.grades, 'gradeHistory',
      target: 'grades-history', requiresAction: true),
  TutorialStep(TutorialChapter.grades, 'averages', target: 'grades-averages'),
  TutorialStep(TutorialChapter.grades, 'gradeFilters',
      target: 'grades-filters'),
  TutorialStep(TutorialChapter.grades, 'view', target: 'grades-subject'),
  TutorialStep(TutorialChapter.grades, 'absenceLink', target: 'grades-absence'),
  TutorialStep(TutorialChapter.grades, 'calculator',
      target: 'grades-calculator', requiresAction: true),
  TutorialStep(TutorialChapter.grades, 'calculatorImport',
      target: 'calculator-import'),
  TutorialStep(TutorialChapter.grades, 'calculatorAdd',
      target: 'calculator-add'),
  TutorialStep(TutorialChapter.grades, 'calculatorTarget',
      target: 'calculator-target'),
  TutorialStep(TutorialChapter.absences, 'absenceOverview',
      target: 'absences-page'),
  TutorialStep(TutorialChapter.absences, 'absenceStatistics',
      target: 'absences-statistics'),
  TutorialStep(TutorialChapter.absences, 'futureAbsence',
      target: 'absences-add'),
  TutorialStep(TutorialChapter.absences, 'absenceHistory',
      target: 'absences-history'),
  TutorialStep(TutorialChapter.calendar, 'navigation',
      target: 'calendar-navigation'),
  TutorialStep(TutorialChapter.calendar, 'lessons', target: 'calendar-week'),
  TutorialStep(TutorialChapter.calendar, 'calendarDetails',
      target: 'calendar-week', openedTarget: 'calendar-detail'),
  TutorialStep(TutorialChapter.calendar, 'calendarEntries',
      target: 'calendar-week', openedTarget: 'calendar-detail'),
  TutorialStep(TutorialChapter.calendar, 'abbreviations',
      target: 'calendar-nicks'),
  TutorialStep(TutorialChapter.calendar, 'substitutions',
      target: 'calendar-substitutions'),
  TutorialStep(TutorialChapter.calendar, 'calendarFilters',
      target: 'calendar-filters'),
  TutorialStep(TutorialChapter.exams, 'examOverview', target: 'exams-page'),
  TutorialStep(TutorialChapter.exams, 'examCards', target: 'exams-card'),
  TutorialStep(TutorialChapter.exams, 'studyPlan',
      target: 'exams-card', openedTarget: 'exams-plan', requiresAction: true),
  TutorialStep(TutorialChapter.exams, 'examDetails',
      target: 'exams-card', openedTarget: 'exams-notes', requiresAction: true),
  TutorialStep(TutorialChapter.exams, 'examFiles',
      target: 'exams-card', openedTarget: 'exams-files', requiresAction: true),
  TutorialStep(TutorialChapter.exams, 'weekView',
      target: 'exams-week', openedTarget: 'exams-week-navigation'),
  TutorialStep(TutorialChapter.other, 'classRegister',
      target: 'class-register-page'),
  TutorialStep(TutorialChapter.other, 'materials', target: 'materials-page'),
  TutorialStep(TutorialChapter.other, 'homework',
      target: 'homework-summary-page'),
  TutorialStep(TutorialChapter.other, 'certificate',
      target: 'certificate-page'),
  TutorialStep(TutorialChapter.other, 'messages', target: 'messages-page'),
];

class TutorialService extends ChangeNotifier {
  static const _offeredKey = 'tutorial.v2.offered';
  static const _progressKey = 'tutorial.v2.progress';
  static const _languageKey = 'tutorial.v2.language';
  static const _completedPrefix = 'tutorial.v2.completed.';
  OverlayEntry? _entry;
  AppLocalizations? _l10n;
  List<TutorialStep> _active = const [];
  int _index = 0;
  bool _actionComplete = false;
  bool _checkingOffer = false;
  bool _starting = false;
  bool _fullTour = false;
  Timer? _tracking;
  Route<dynamic>? _rootRoute;
  Route<dynamic>? _nestedRoute;
  bool suspended = false;
  bool _advancing = false;
  Rect? _lastRect;
  int _missingTicks = 0;
  UtcDateTime? _pendingReminderDay;
  String? _pendingReminderText;
  Set<int> _previousReminderIds = {};
  int? _createdReminderId;
  UtcDateTime? _createdReminderDay;
  bool _dashboardFuture = true;
  bool get dashboardFuture => _dashboardFuture;
  set dashboardFuture(bool value) => _dashboardFuture = value;
  String? _targetFor(bool covered) {
    if (step.openedTarget != null &&
        tutorialTargets.rectFor(step.openedTarget) != null) {
      final root = _top(navigatorKey);
      if (root != _rootRoute &&
          tutorialTargets.routeFor(step.openedTarget) != root) {
        return null;
      }
      return step.openedTarget;
    }
    return covered ? null : step.target;
  }

  String? get highlightTarget => _targetFor(suspended);

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
    _missingTicks = 0;
  }

  void _track() {
    if (!active || _advancing) return;
    final covered =
        _top(navigatorKey) != _rootRoute || _top(nestedNavKey) != _nestedRoute;
    final rect = tutorialTargets.rectFor(_targetFor(covered));
    if (covered &&
        step.requiresAction &&
        ![
          'reminders',
          'deleteReminder',
          'assessmentShortcuts',
          'deleteAssessment'
        ].contains(step.key)) {
      _actionComplete = true;
    }
    if (covered &&
        step.key == 'calculator' &&
        tutorialTargets.rectFor('calculator-import') != null) {
      _actionComplete = true;
      unawaited(next());
      return;
    }
    if (covered != suspended || rect != _lastRect) {
      final opened = covered && !suspended;
      suspended = covered;
      _lastRect = rect;
      notifyListeners();
      if (opened) unawaited(tutorialTargets.reveal(step.openedTarget));
    }
    if (!covered &&
        rect == null &&
        ++_missingTicks == 30 &&
        ![
          'reminders',
          'deleteReminder',
          'assessmentShortcuts',
          'deleteAssessment'
        ].contains(step.key)) {
      _actionComplete = true;
      notifyListeners();
    }
    if (rect != null) _missingTicks = 0;
  }

  bool get active => _entry != null;
  TutorialStep get step => _active[_index];
  int get index => _index;
  int get length => _active.length;
  bool get canContinue => !step.requiresAction || _actionComplete;
  String text(String suffix) => _l10n?.text('tutorial.$suffix') ?? suffix;
  String stepTitle() => text('step.${step.key}.title');
  String stepBody() => text('step.${step.key}.body');

  void reminderSubmitted(Day day, String message) {
    if (!active || !['reminders', 'assessmentShortcuts'].contains(step.key)) {
      return;
    }
    _pendingReminderDay = day.date;
    _pendingReminderText = message;
    _previousReminderIds = day.homework.map((item) => item.id).toSet();
    _createdReminderId = null;
    _createdReminderDay = null;
  }

  bool observeDashboardDays(Iterable<Day> days) {
    final date = _pendingReminderDay;
    final message = _pendingReminderText;
    if (!active || date == null || message == null) return false;
    for (final day in days.where((item) => item.date == date)) {
      for (final item in day.homework) {
        if (item.type == HomeworkType.homework &&
            !_previousReminderIds.contains(item.id) &&
            (item.subtitle == message || item.title == message)) {
          _createdReminderId = item.id;
          _createdReminderDay = date;
          _pendingReminderDay = null;
          _pendingReminderText = null;
          completeRequiredAction('dashboard-reminder');
          unawaited(next());
          return true;
        }
      }
    }
    return false;
  }

  bool isCreatedReminder(Day day, Homework item) =>
      active &&
      _createdReminderId == item.id &&
      _createdReminderDay == day.date;

  void reminderDeleted(int id) {
    if (_createdReminderId != id) return;
    _createdReminderId = null;
    _createdReminderDay = null;
    completeRequiredAction('dashboard-created-reminder');
    unawaited(next());
  }

  Future<bool> isChapterCompleted(TutorialChapter chapter) async =>
      (await SharedPreferences.getInstance())
          .getBool('$_completedPrefix${chapter.name}') ??
      false;

  Future<void> maybeOffer(BuildContext context) async {
    // Widget tests construct dashboard fragments without a real login/device.
    if (WidgetsBinding.instance.runtimeType
        .toString()
        .contains('TestWidgetsFlutterBinding')) {
      return;
    }
    if (_checkingOffer || active) return;
    _checkingOffer = true;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_offeredKey) == true || !context.mounted) {
      _checkingOffer = false;
      return;
    }
    await prefs.setBool(_offeredKey, true);
    if (!context.mounted) {
      _checkingOffer = false;
      return;
    }
    final begin = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
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
    if (begin == true && context.mounted) {
      final language = await _chooseLanguage(context);
      if (language != null && context.mounted) {
        await startAll(context, language: language);
      }
    }
    _checkingOffer = false;
  }

  Future<AppLanguage?> _chooseLanguage(BuildContext context) =>
      showDialog<AppLanguage>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.l10n.text('tutorial.language.title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(dialogContext.l10n.text('tutorial.languageScope')),
              for (final language in AppLanguage.values)
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(_languageName(language)),
                  onTap: () => Navigator.pop(dialogContext, language),
                ),
            ],
          ),
        ),
      );

  String _languageName(AppLanguage language) => switch (language) {
        AppLanguage.de => 'Deutsch',
        AppLanguage.it => 'Italiano',
        AppLanguage.en => 'English',
        AppLanguage.lld => 'Ladin',
      };

  Future<void> startAll(BuildContext context, {AppLanguage? language}) async {
    if (_starting) return;
    _starting = true;
    try {
      language ??= await _chooseLanguage(context);
      if (language == null || !context.mounted) return;
      await _start(context, _steps, language: language);
    } finally {
      _starting = false;
    }
  }

  Future<void> startChapter(
      BuildContext context, TutorialChapter chapter) async {
    if (_starting) return;
    _starting = true;
    try {
      await _start(
          context, _steps.where((item) => item.chapter == chapter).toList());
    } finally {
      _starting = false;
    }
  }

  Future<void> _start(BuildContext context, List<TutorialStep> steps,
      {AppLanguage? language}) async {
    unawaited(AnalyticsService.product
        .event('onboarding_step', {'step_id': 'welcome', 'action': 'shown'}));
    await cancel(saveProgress: false);
    final prefs = await SharedPreferences.getInstance();
    final selected = language ?? appLanguageController.language;
    if (language != null) {
      await actions.settingsActions.setLanguage(selected.code);
    }
    await prefs.setString(_languageKey, selected.code);
    _l10n = await AppLocalizations.load(selected.locale);
    _active = steps;
    _fullTour = steps.length == _steps.length;
    _index = 0;
    if (_fullTour) await prefs.remove(_progressKey);
    _actionComplete = false;
    _pendingReminderDay = null;
    _pendingReminderText = null;
    _createdReminderId = null;
    _createdReminderDay = null;
    await _showPage(step);
    _entry = OverlayEntry(builder: (_) => TutorialOverlay(service: this));
    final overlay = navigatorKey?.currentState?.overlay;
    if (overlay == null) {
      _entry = null;
      return;
    }
    overlay.insert(_entry!);
    notifyListeners();
    _captureRoutes();
    _tracking =
        Timer.periodic(const Duration(milliseconds: 80), (_) => _track());
    _refreshAfterNavigation();
  }

  void completeRequiredAction(String target) {
    if (!active || step.target != target || !step.requiresAction) return;
    _actionComplete = true;
    notifyListeners();
  }

  Future<void> next() async {
    if (_advancing || !active || !canContinue) return;
    _advancing = true;
    try {
      final enteringCalculator = step.key == 'calculator' &&
          tutorialTargets.rectFor('calculator-import') != null;
      if (!enteringCalculator) {
        // Close only the routes opened while exploring this step. Never submit
        // a form on the user's behalf; its Save button remains the only commit.
        for (final entry in [
          (navigatorKey, _rootRoute),
          (nestedNavKey, _nestedRoute)
        ]) {
          final baseline = entry.$2;
          if (baseline != null && baseline.isActive) {
            entry.$1?.currentState?.popUntil((route) => route == baseline);
          }
        }
      }
      if (_index + 1 >= _active.length) {
        await _finish();
        return;
      }
      final previous = step;
      _index++;
      _actionComplete = false;
      if (previous.key == 'past' && !_dashboardFuture) {
        await actions.dashboardActions.switchFuture();
      }
      if (step.chapter != previous.chapter ||
          _pageGroup(step) != _pageGroup(previous)) {
        if (!(previous.key == 'calculator' &&
            step.key == 'calculatorImport' &&
            tutorialTargets.rectFor('calculator-import') != null)) {
          await _showPage(step);
        }
      }
      if (!active) return;
      _captureRoutes();
      if (_fullTour) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_progressKey, _index);
      }
      notifyListeners();
      _refreshAfterNavigation();
    } finally {
      _advancing = false;
    }
  }

  Future<void> _finish() async {
    unawaited(AnalyticsService.product.event(
        'onboarding_step', {'step_id': 'complete', 'action': 'completed'}));
    final prefs = await SharedPreferences.getInstance();
    for (final chapter in _active.map((e) => e.chapter).toSet()) {
      await prefs.setBool('$_completedPrefix${chapter.name}', true);
    }
    if (_fullTour) await prefs.remove(_progressKey);
    await cancel(saveProgress: false);
  }

  Future<void> cancel({bool saveProgress = true}) async {
    if (saveProgress && active) {
      unawaited(AnalyticsService.product.event(
          'onboarding_step', {'step_id': 'complete', 'action': 'skipped'}));
    }
    _tracking?.cancel();
    _tracking = null;
    if (saveProgress && active && _fullTour) {
      await (await SharedPreferences.getInstance())
          .setInt(_progressKey, _index);
    }
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    _active = const [];
    _index = 0;
    _fullTour = false;
    _pendingReminderDay = null;
    _pendingReminderText = null;
    _createdReminderId = null;
    _createdReminderDay = null;
    notifyListeners();
  }

  String _pageGroup(TutorialStep value) {
    if (value.key.startsWith('calculator') && value.key != 'calculator') {
      return 'calculator';
    }
    if (value.chapter == TutorialChapter.other) return value.key;
    return value.chapter.name;
  }

  Future<void> _showPage(TutorialStep value) async {
    // Close calculator/detail routes before switching the responsive body.
    navigatorKey?.currentState?.popUntil((route) => route.isFirst);
    switch (value.chapter) {
      case TutorialChapter.dashboard:
        scaffoldKey?.currentState?.goHome();
      case TutorialChapter.grades:
        if (value.key.startsWith('calculator') && value.key != 'calculator') {
          await actions.routingActions.showGradeCalculator();
        } else {
          await actions.routingActions.showGrades();
        }
      case TutorialChapter.absences:
        await actions.routingActions.showAbsences();
      case TutorialChapter.calendar:
        await actions.routingActions.showCalendar();
      case TutorialChapter.exams:
        scaffoldKey?.currentState?.selectContentWidget(
            const ExamCalendarContainer(), Pages.examCalendar);
      case TutorialChapter.other:
        _showOtherPage(value.key);
    }
  }

  void _showOtherPage(String key) {
    final state = scaffoldKey?.currentState;
    if (state == null) return;
    switch (key) {
      case 'classRegister':
        state.selectContentWidget(
            ClassRegisterPage(key: UniqueKey()), Pages.classRegister);
      case 'materials':
        state.selectContentWidget(
            CourseMaterialsPage(key: UniqueKey()), Pages.courseMaterials);
      case 'homework':
        state.selectContentWidget(
            const HomeworkSummaryPage(), Pages.homeworkSummary);
      case 'certificate':
        actions.routingActions.showCertificate();
      case 'messages':
        actions.routingActions.showMessages();
    }
  }

  void _refreshAfterNavigation() {
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (!active) return;
      unawaited(tutorialTargets.reveal(step.target).then((_) {
        if (active) notifyListeners();
      }));
    });
  }
}

final tutorialService = TutorialService();
