import 'dart:async';

import 'package:dr/container/exam_calendar_container.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/class_register_page.dart';
import 'package:dr/ui/course_materials_page.dart';
import 'package:dr/ui/homework_summary_page.dart';
import 'package:dr/tutorial/tutorial_overlay.dart';
import 'package:flutter/material.dart';
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
      {this.target, this.requiresAction = false});
  final TutorialChapter chapter;
  final String key;
  final String? target;
  final bool requiresAction;
}

class TutorialTargetRegistry {
  final Map<String, BuildContext> _contexts = {};
  void register(String id, BuildContext context) => _contexts[id] = context;
  void remove(String id, BuildContext context) {
    if (identical(_contexts[id], context)) _contexts.remove(id);
  }

  Rect? rectFor(String? id) {
    final context = id == null ? null : _contexts[id];
    final box = context?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> reveal(String? id) async {
    final context = id == null ? null : _contexts[id];
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
      target: 'dashboard-reminder'),
  TutorialStep(TutorialChapter.dashboard, 'assessmentShortcuts',
      target: 'dashboard-reminder'),
  TutorialStep(TutorialChapter.grades, 'semester', target: 'grades-semester'),
  TutorialStep(TutorialChapter.grades, 'gradeHistory',
      target: 'grades-history', requiresAction: true),
  TutorialStep(TutorialChapter.grades, 'averages', target: 'grades-averages'),
  TutorialStep(TutorialChapter.grades, 'gradeFilters', target: 'grades-list'),
  TutorialStep(TutorialChapter.grades, 'view', target: 'grades-list'),
  TutorialStep(TutorialChapter.grades, 'absenceLink', target: 'grades-list'),
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
      target: 'absences-page'),
  TutorialStep(TutorialChapter.calendar, 'navigation',
      target: 'calendar-navigation'),
  TutorialStep(TutorialChapter.calendar, 'lessons', target: 'calendar-week'),
  TutorialStep(TutorialChapter.calendar, 'calendarDetails',
      target: 'calendar-week'),
  TutorialStep(TutorialChapter.calendar, 'calendarEntries',
      target: 'calendar-week'),
  TutorialStep(TutorialChapter.calendar, 'abbreviations',
      target: 'calendar-week'),
  TutorialStep(TutorialChapter.calendar, 'substitutions',
      target: 'calendar-substitutions'),
  TutorialStep(TutorialChapter.calendar, 'calendarFilters',
      target: 'calendar-page'),
  TutorialStep(TutorialChapter.exams, 'examOverview', target: 'exams-page'),
  TutorialStep(TutorialChapter.exams, 'examCards', target: 'exams-page'),
  TutorialStep(TutorialChapter.exams, 'studyPlan', target: 'exams-page'),
  TutorialStep(TutorialChapter.exams, 'examDetails', target: 'exams-page'),
  TutorialStep(TutorialChapter.exams, 'weekView', target: 'exams-week'),
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
  bool _fullTour = false;

  bool get active => _entry != null;
  TutorialStep get step => _active[_index];
  int get index => _index;
  int get length => _active.length;
  bool get canContinue => !step.requiresAction || _actionComplete;
  String text(String suffix) => _l10n?.text('tutorial.$suffix') ?? suffix;
  String stepTitle() => text('step.${step.key}.title');
  String stepBody() => text('step.${step.key}.body');

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
    await _start(context, _steps, language: language, resume: language == null);
  }

  Future<void> startChapter(
      BuildContext context, TutorialChapter chapter) async {
    await _start(
        context, _steps.where((item) => item.chapter == chapter).toList());
  }

  Future<void> _start(BuildContext context, List<TutorialStep> steps,
      {AppLanguage? language, bool resume = false}) async {
    await cancel(saveProgress: false);
    final prefs = await SharedPreferences.getInstance();
    final selected =
        language ?? AppLanguage.fromCode(prefs.getString(_languageKey));
    await prefs.setString(_languageKey, selected.code);
    _l10n = await AppLocalizations.load(selected.locale);
    _active = steps;
    _fullTour = steps.length == _steps.length;
    final savedIndex = resume ? prefs.getInt(_progressKey) : null;
    _index = savedIndex == null ? 0 : savedIndex.clamp(0, steps.length - 1);
    _actionComplete = false;
    await _showPage(step);
    _entry = OverlayEntry(builder: (_) => TutorialOverlay(service: this));
    final overlay = navigatorKey?.currentState?.overlay;
    if (overlay == null) {
      _entry = null;
      return;
    }
    overlay.insert(_entry!);
    _refreshAfterNavigation();
  }

  void completeRequiredAction(String target) {
    if (!active || step.target != target || !step.requiresAction) return;
    _actionComplete = true;
    notifyListeners();
  }

  Future<void> next() async {
    if (!canContinue) return;
    if (_index + 1 >= _active.length) {
      await _finish();
      return;
    }
    final previous = step;
    _index++;
    _actionComplete = false;
    if (step.chapter != previous.chapter ||
        _pageGroup(step) != _pageGroup(previous)) {
      await _showPage(step);
    }
    if (_fullTour) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_progressKey, _index);
    }
    notifyListeners();
    _refreshAfterNavigation();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    for (final chapter in _active.map((e) => e.chapter).toSet()) {
      await prefs.setBool('$_completedPrefix${chapter.name}', true);
    }
    if (_fullTour) await prefs.remove(_progressKey);
    await cancel(saveProgress: false);
  }

  Future<void> cancel({bool saveProgress = true}) async {
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
  }

  String _pageGroup(TutorialStep value) {
    if (value.key.startsWith('calculator')) return 'calculator';
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
        if (value.key.startsWith('calculator')) {
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
