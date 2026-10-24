import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:dr/android_widget_snapshot.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final friday = UtcDateTime(2026, 3, 27);
  final monday = UtcDateTime(2026, 3, 30);
  AppState planningState(
      {List<Homework> tasks = const [],
      List<HomeworkExam> exams = const [],
      bool dashboardLoaded = true}) {
    final days = [
      buildCalendarDay(date: friday, hours: [
        buildCalendarHour(subject: 'Deutsch'),
        buildCalendarHour(subject: 'Kunst'),
      ]),
      buildCalendarDay(date: monday, hours: [
        buildCalendarHour(subject: 'Mathematik', homeworkExams: exams),
        buildCalendarHour(subject: 'Mathematik'),
        buildCalendarHour(subject: 'Englisch'),
      ]),
    ];
    return AppState((b) {
      b.loginState
        ..loggedIn = true
        ..username = 'private-user';
      b.url = 'https://private-school.example';
      b.calendarState.days =
          MapBuilder({for (final day in days) day.date: day});
      if (dashboardLoaded) {
        b.dashboardState.allDays =
            ListBuilder([buildDay(date: monday, homework: tasks)]);
      }
    });
  }

  setUp(() => mockNow = fixtureNow);
  tearDown(() => mockNow = null);

  test('Monday preparation deduplicates subjects and compares Friday bag', () {
    final snapshot = buildAndroidWidgetSnapshot(planningState());
    expect(snapshot.schoolBag.items.map((i) => '${i.title}:${i.subject}'), [
      'Einpacken:Mathematik',
      'Einpacken:Englisch',
      'Kann heraus:Deutsch',
      'Kann heraus:Kunst',
    ]);
    expect(snapshot.schoolBag.subtitle, contains('30.03.2026'));
    expect(snapshot.planningValidOn, '2026-03-28');
    expect(snapshot.preparation.items, isEmpty);
    expect(snapshot.preparation.emptyMessage, contains('Keine offenen'));
    final json = jsonEncode(snapshot.toJson());
    expect(json, isNot(contains('private-user')));
    expect(json, isNot(contains('private-school')));
  });

  test('open tasks retain materials and omit done, deleted and grade entries',
      () {
    final snapshot = buildAndroidWidgetSnapshot(planningState(tasks: [
      buildHomework(
          id: 1,
          label: 'Deutsch',
          title: '<b>Lesen</b>',
          subtitle: 'S. 4 &amp; 5'),
      buildHomework(id: 2, checked: true, title: 'DONE'),
      buildHomework(id: 3, deleted: true, title: 'DELETED'),
      buildHomework(id: 4, type: HomeworkType.grade, title: 'GRADE'),
      buildHomework(
          id: 5, type: HomeworkType.gradeGroup, title: 'Test', warning: true),
    ], exams: [
      buildHomeworkExam(id: 2, name: 'DONE'),
      buildHomeworkExam(id: 5, name: 'Test')
    ]));
    expect(snapshot.preparation.items.map((i) => i.title), ['Lesen', 'Test']);
    expect(snapshot.preparation.items.first.subtitle, 'S. 4 & 5');
    expect(snapshot.preparation.items.last.warning, isTrue);
    expect(
        snapshot.schoolBag.items
            .where((i) => i.title == 'Kann heraus')
            .map((i) => i.subject),
        ['Kunst']);
  });

  test('calendar tasks supplement missing homework with a warning', () {
    final snapshot = buildAndroidWidgetSnapshot(planningState(
        dashboardLoaded: false,
        exams: [buildHomeworkExam(name: 'Prüfung', warning: true)]));
    expect(snapshot.preparation.items.first.title, 'Prüfung');
    expect(
        snapshot.preparation.items.last.title, contains('nicht vollständig'));
    expect(snapshot.preparation.items.last.warning, isTrue);
  });

  test('unknown weekdays do not get skipped in favour of a later loaded day',
      () {
    mockNow = friday;
    final state =
        planningState().rebuild((b) => b.calendarState.days.remove(monday));
    final snapshot = buildAndroidWidgetSnapshot(state);
    expect(snapshot.schoolBag.items, isEmpty);
    expect(snapshot.preparation.items, isEmpty);
    expect(snapshot.schoolBag.emptyMessage, contains('aktuelle Daten'));
  });

  test('explicit holidays are skipped and weekend lessons are respected', () {
    var state = planningState().rebuild(
        (b) => b.calendarState.days[monday] = buildCalendarDay(date: monday));
    final tuesday = UtcDateTime(2026, 3, 31);
    state = state.rebuild((b) => b.calendarState.days[tuesday] =
        buildCalendarDay(
            date: tuesday, hours: [buildCalendarHour(subject: 'Sport')]));
    expect(buildAndroidWidgetSnapshot(state).schoolBag.items.first.subject,
        'Sport');
    final sunday = UtcDateTime(2026, 3, 29);
    state = state.rebuild((b) => b.calendarState.days[sunday] =
        buildCalendarDay(
            date: sunday, hours: [buildCalendarHour(subject: 'Musik')]));
    expect(buildAndroidWidgetSnapshot(state).schoolBag.items.first.subject,
        'Musik');
  });

  test('stale or undated timetable never produces packing advice', () {
    for (final fetched in [
      null,
      fixtureNow.subtract(const Duration(days: 8))
    ]) {
      final state = planningState();
      final outdated = state.calendarState.days[monday]!
          .rebuild((b) => b.lastFetched = fetched);
      final snapshot = buildAndroidWidgetSnapshot(
          state.rebuild((b) => b.calendarState.days[monday] = outdated));
      expect(snapshot.schoolBag.items, isEmpty);
      expect(snapshot.preparation.items, isEmpty);
    }
  });

  test('missing previous timetable does not invent removal advice', () {
    final state =
        planningState().rebuild((b) => b.calendarState.days.remove(friday));
    expect(
        buildAndroidWidgetSnapshot(state)
            .schoolBag
            .items
            .every((i) => i.title == 'Einpacken'),
        isTrue);
  });

  test('logout, storage restriction and app lock redact populated snapshots',
      () {
    final state = planningState(tasks: [buildHomework(title: 'SECRET')]);
    for (final blocked in [
      state.rebuild((b) => b.loginState.loggedIn = false),
      state.rebuild((b) => b.settingsState.noDataSaving = true),
      state.rebuild((b) => b.settingsState.biometricAppLockEnabled = true),
    ]) {
      final snapshot = buildAndroidWidgetSnapshot(blocked);
      expect(snapshot.schoolBag.items, isEmpty);
      expect(snapshot.preparation.items, isEmpty);
      expect(jsonEncode(snapshot.toJson()), isNot(contains('SECRET')));
      expect(jsonEncode(snapshot.toJson()), isNot(contains('Mathematik')));
    }
  });

  test('task text is concise and widgets follow the app language', () {
    for (final language in ['de', 'it', 'en']) {
      final state = planningState(tasks: [buildHomework(title: 'A' * 400)])
          .rebuild((b) => b.settingsState.languageCode = language);
      final snapshot = buildAndroidWidgetSnapshot(state);
      expect(snapshot.preparation.items.first.title.length,
          lessThanOrEqualTo(180));
      expect(snapshot.schoolBag.title,
          {'de': 'Schultasche', 'it': 'Zaino', 'en': 'School bag'}[language]);
    }
  });
}
