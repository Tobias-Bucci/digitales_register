import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/calendar_actions.dart';
import 'package:dr/actions/grades_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Store<AppState, AppStateBuilder, AppActions> store;

  setUp(() {
    store = Store<AppState, AppStateBuilder, AppActions>(
      appReducerBuilder.build(),
      AppState(),
      AppActions(),
      middleware: middleware(includeErrorMiddleware: false),
    );
  });

  test('parse absences from maps and encoded json', () {
    store.actions.absencesActions.loaded(absencesJson);
    store.actions.absencesActions.loaded(json.encode(absencesJson));
    store.actions.absencesActions
        .loaded(json.decode(json.encode(absencesJson)) as Map<String, dynamic>);

    expect(store.state.absencesState.absences, hasLength(2));
    expect(store.state.absencesState.absences.first.absences, hasLength(4));
    expect(store.state.absencesState.absences.first.reason, contains('fit'));
    expect(store.state.absencesState.statistic!.delayed, 0);
    expect(store.state.absencesState.canEdit, isTrue);
  });

  test('parse calendar days and merge additional pages', () {
    store.actions.calendarActions.loaded(_calendarLoaded(calendarPageOne));
    store.actions.calendarActions.loaded(_calendarLoaded(calendarPageTwo));

    expect(store.state.calendarState.days, hasLength(2));

    final firstDay = store.state.calendarState.days[UtcDateTime(2022, 9, 28)]!;
    expect(firstDay.hours, hasLength(1));
    expect(firstDay.hours.single.subject, 'Projekttag');
    expect(firstDay.hours.single.timeSpans, hasLength(2));
    expect(firstDay.hours.single.homeworkExams.single.name, 'Arbeitsblatt');

    final secondDay = store.state.calendarState.days[UtcDateTime(2022, 9, 29)]!;
    expect(secondDay.hours.single.subject, 'Mathematik');
  });

  test('generates automatic subject nick from first and last word', () {
    expect(
      generateAutomaticSubjectNick('Soziale Bildung'),
      'SB',
    );
    expect(
      generateAutomaticSubjectNick('Deutsch als Zweitsprache'),
      'DZ',
    );
  });

  test('does not generate automatic subject nick outside two or three words',
      () {
    expect(generateAutomaticSubjectNick('Informatik'), isNull);
    expect(generateAutomaticSubjectNick('Ein Fach Name Test'), isNull);
  });

  test('detects substitute lessons from a stable teacher baseline', () async {
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-03',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
        toHour: 4,
      )),
    );
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-10',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
        toHour: 4,
      )),
    );
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-17',
        teacherFirstName: 'Doris',
        teacherLastName: 'Hilpold',
      )),
    );

    final regularHour =
        store.state.calendarState.days[UtcDateTime(2026, 4, 10)]!.hours.single;
    final substituteHour =
        store.state.calendarState.days[UtcDateTime(2026, 4, 17)]!.hours.single;

    expect(regularHour.isDetectedSubstitute, isFalse);
    expect(substituteHour.isDetectedSubstitute, isTrue);
  });

  test('does not mark lessons without a stable baseline as substitute',
      () async {
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-17',
        teacherFirstName: 'Doris',
        teacherLastName: 'Hilpold',
      )),
    );

    final hour =
        store.state.calendarState.days[UtcDateTime(2026, 4, 17)]!.hours.single;
    expect(hour.isDetectedSubstitute, isFalse);
  });

  test('never marks lessons with multiple teachers as substitute', () {
    store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-03',
        teacherFirstName: 'Anna',
        teacherLastName: 'Auer',
        additionalTeachers: const [
          ('Berta', 'Bacher'),
        ],
      )),
    );
    store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-10',
        teacherFirstName: 'Berta',
        teacherLastName: 'Bacher',
        additionalTeachers: const [
          ('Anna', 'Auer'),
        ],
      )),
    );

    final hour =
        store.state.calendarState.days[UtcDateTime(2026, 4, 10)]!.hours.single;
    expect(hour.isDetectedSubstitute, isFalse);
  });

  test('respects configured primary teachers for a subject', () async {
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-03',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-10',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-17',
        teacherFirstName: 'Doris',
        teacherLastName: 'Hilpold',
      )),
    );
    await _flushAsyncActions();

    expect(
      store.state.calendarState.days[UtcDateTime(2026, 4, 17)]!.hours.single
          .isDetectedSubstitute,
      isTrue,
    );

    await store.actions.settingsActions.substitutePrimaryTeachers(
      BuiltMap<String, BuiltList<String>>({
        'Informatik': BuiltList<String>(const ['Doris Hilpold']),
      }),
    );
    await store.actions.settingsActions.substitutePrimaryTeachersLockedSubjects(
      BuiltList<String>(const ['Informatik']),
    );
    await _recalculateSubstitutesFromState(store);
    await _flushAsyncActions();

    expect(
      store.state.calendarState.days[UtcDateTime(2026, 4, 17)]!.hours.single
          .isDetectedSubstitute,
      isFalse,
    );
  });

  test('accepts multiple configured primary teachers for a subject', () async {
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-03',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-10',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await _flushAsyncActions();

    await store.actions.settingsActions.substitutePrimaryTeachers(
      BuiltMap<String, BuiltList<String>>({
        'Informatik': BuiltList<String>(
          const ['Doris Hilpold', 'Christoph Holzer'],
        ),
      }),
    );
    await _recalculateSubstitutesFromState(store);
    await _flushAsyncActions();

    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-17',
        teacherFirstName: 'Doris',
        teacherLastName: 'Hilpold',
      )),
    );
    await _flushAsyncActions();
    await _recalculateSubstitutesFromState(store);
    await _flushAsyncActions();

    expect(
      store.state.calendarState.days[UtcDateTime(2026, 4, 17)]!.hours.single
          .isDetectedSubstitute,
      isFalse,
    );
  });

  test('ignores substitute detection for locked subjects without teachers',
      () async {
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-03',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-10',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await _flushAsyncActions();

    await store.actions.settingsActions.substitutePrimaryTeachers(
      BuiltMap<String, BuiltList<String>>({
        'Informatik': BuiltList<String>(),
      }),
    );
    await store.actions.settingsActions.substitutePrimaryTeachersLockedSubjects(
      BuiltList<String>(const ['Informatik']),
    );
    await _recalculateSubstitutesFromState(store);
    await _flushAsyncActions();

    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-17',
        teacherFirstName: 'Doris',
        teacherLastName: 'Hilpold',
      )),
    );
    await _flushAsyncActions();
    await _recalculateSubstitutesFromState(store);
    await _flushAsyncActions();

    expect(
      store.state.settingsState.substitutePrimaryTeachers['Informatik'],
      BuiltList<String>(),
    );
    expect(
      store.state.calendarState.days[UtcDateTime(2026, 4, 17)]!.hours.single
          .isDetectedSubstitute,
      isFalse,
    );
  });

  test('auto-populates stable primary teachers per subject', () {
    return _runAutoPopulatePrimaryTeachersTest(store);
  });

  test('auto-populate keeps only the most frequent single teacher per subject',
      () async {
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-03',
        teacherFirstName: 'Anna',
        teacherLastName: 'Auer',
      )),
    );
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-10',
        teacherFirstName: 'Anna',
        teacherLastName: 'Auer',
        additionalTeachers: const [('Berta', 'Bacher')],
      )),
    );
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-17',
        teacherFirstName: 'Clara',
        teacherLastName: 'Costa',
      )),
    );
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-24',
        teacherFirstName: 'Clara',
        teacherLastName: 'Costa',
      )),
    );
    await _flushAsyncActions();

    expect(
      store.state.settingsState.substitutePrimaryTeachers['Informatik'],
      BuiltList<String>(const <String>['Clara Costa']),
    );
  });

  test('manual substitute teacher changes stay locked against auto updates',
      () async {
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-03',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-10',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await _flushAsyncActions();

    await store.actions.settingsActions.substitutePrimaryTeachers(
      BuiltMap<String, BuiltList<String>>({
        'Informatik': BuiltList<String>(const ['Doris Hilpold']),
      }),
    );
    await store.actions.settingsActions.substitutePrimaryTeachersLockedSubjects(
      BuiltList<String>(const ['Informatik']),
    );
    await _flushAsyncActions();

    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-17',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await _flushAsyncActions();

    expect(
      store.state.settingsState.substitutePrimaryTeachers['Informatik'],
      BuiltList<String>(const <String>['Doris Hilpold']),
    );
  });

  test('auto-detected primary teacher is not replaced automatically later',
      () async {
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-03',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-10',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await _flushAsyncActions();

    expect(
      store.state.settingsState.substitutePrimaryTeachers['Informatik'],
      BuiltList<String>(const <String>['Christoph Holzer']),
    );

    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-17',
        teacherFirstName: 'Doris',
        teacherLastName: 'Hilpold',
      )),
    );
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-24',
        teacherFirstName: 'Doris',
        teacherLastName: 'Hilpold',
      )),
    );
    await _flushAsyncActions();

    expect(
      store.state.settingsState.substitutePrimaryTeachers['Informatik'],
      BuiltList<String>(const <String>['Christoph Holzer']),
    );
  });

  test('manual primary teacher override takes precedence over detected teacher',
      () async {
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-03',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-10',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await _flushAsyncActions();

    await store.actions.settingsActions.substitutePrimaryTeachers(
      BuiltMap<String, BuiltList<String>>({
        'Informatik': BuiltList<String>(const ['Doris Hilpold']),
      }),
    );
    await store.actions.settingsActions.substitutePrimaryTeachersLockedSubjects(
      BuiltList<String>(const ['Informatik']),
    );
    await _recalculateSubstitutesFromState(store);
    await _flushAsyncActions();

    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-17',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await _flushAsyncActions();
    await _recalculateSubstitutesFromState(store);
    await _flushAsyncActions();

    expect(
      store.state.calendarState.days[UtcDateTime(2026, 4, 17)]!.hours.single
          .isDetectedSubstitute,
      isTrue,
    );
  });

  test('disabling substitute detection clears existing substitute markers',
      () async {
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-03',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-10',
        teacherFirstName: 'Christoph',
        teacherLastName: 'Holzer',
      )),
    );
    await store.actions.calendarActions.loaded(
      _calendarLoaded(_calendarPayloadForDate(
        date: '2026-04-17',
        teacherFirstName: 'Doris',
        teacherLastName: 'Hilpold',
      )),
    );
    await _flushAsyncActions();

    expect(
      store.state.calendarState.days[UtcDateTime(2026, 4, 17)]!.hours.single
          .isDetectedSubstitute,
      isTrue,
    );

    await store.actions.settingsActions.substituteDetectionEnabled(false);
    await _recalculateSubstitutesFromState(store);
    await _flushAsyncActions();

    expect(
      store.state.calendarState.days[UtcDateTime(2026, 4, 17)]!.hours.single
          .isDetectedSubstitute,
      isFalse,
    );
  });

  test('parse grades list, details, and observations', () {
    store.actions.gradesActions.loaded(
      SubjectsLoadedPayload(
        (b) => b
          ..data = subjectsPayload
          ..semester = Semester.first.toBuilder(),
      ),
    );

    expect(store.state.gradesState.subjects, hasLength(2));
    expect(store.state.gradesState.hasGrades, isTrue);
    expect(
      store.state.gradesState.subjects.first.basicGrades(Semester.first),
      hasLength(1),
    );

    store.actions.gradesActions.detailsLoaded(
      SubjectDetailLoadedPayload(
        (b) => b
          ..data = subjectDetailsPayload
          ..subject = store.state.gradesState.subjects.first.toBuilder()
          ..semester = Semester.first.toBuilder(),
      ),
    );

    final subject = store.state.gradesState.subjects.first;
    expect(subject.detailEntries(Semester.first), hasLength(2));
    expect(subject.grades[Semester.first]!.single.name, 'Schularbeit 1');
    expect(subject.observations[Semester.first], hasLength(1));
    expect(
        subject.observations[Semester.first]!.single.note, 'Gut vorbereitet');
  });

  test('parse profile', () {
    store.actions.profileActions.loaded(profilePayload);

    expect(
      store.state.profileState,
      ProfileState(
        (b) => b
          ..name = 'Debertol Michael'
          ..codiceFiscale = 'BCCTBS07S23B220B'
          ..email = 'st-debmic-03@vinzentinum.it'
          ..picture = '2GSwZUaN5CTXPPtHMcNEXGwq4rWqvFxA'
          ..username = 'st-debmic-03'
          ..roleName = 'Schüler/in'
          ..sendNotificationEmails = false,
      ),
    );
  });

  test('parse message link attachments from submissions', () {
    store.actions.messagesActions.loaded(<Object>[
      <String, Object?>{
        'id': 2684,
        'fromUserId': 5547,
        'subject': 'Umfrage - sozialpädagogische Workshops',
        'text': '{"ops":[{"insert":"Nachricht\\n"}]}',
        'timeSent': '2026-04-16 15:44:30',
        'recipientString': 'Alle Schüler/innen',
        'fromName': 'Koch Marie Sophie',
        'submissions': <Object>[
          <String, Object?>{
            'id': 938,
            'messageId': 2684,
            'title': 'Umfrage - sozialpädagogische Workshops',
            'type': 'link',
            'link': 'https://forms.office.com/Pages/ResponsePage.aspx?id=test',
            'file': null,
            'originalName': null,
            'isDownloadable': true,
          },
        ],
      },
    ]);

    final message = store.state.messagesState.messages.single;
    final attachment = message.attachments.single;
    expect(attachment.type, 'link');
    expect(
      attachment.originalName,
      'Umfrage - sozialpädagogische Workshops',
    );
    expect(
      attachment.link,
      'https://forms.office.com/Pages/ResponsePage.aspx?id=test',
    );
    expect(attachment.file, isNull);
  });
}

Map<String, dynamic> _calendarPayloadForDate({
  required String date,
  required String teacherFirstName,
  required String teacherLastName,
  int hour = 3,
  int toHour = 3,
  List<(String, String)> additionalTeachers = const [],
}) {
  final teachers = <Map<String, dynamic>>[
    {
      'id': 67,
      'firstName': teacherFirstName,
      'lastName': teacherLastName,
    },
    for (final teacher in additionalTeachers)
      {
        'id': teacher.$1.hashCode ^ teacher.$2.hashCode,
        'firstName': teacher.$1,
        'lastName': teacher.$2,
      },
  ];

  final linkedHours = <Map<String, dynamic>>[
    for (var linkedHour = hour + 1; linkedHour <= toHour; linkedHour++)
      _lessonPayload(
        date: date,
        hour: linkedHour,
        toHour: linkedHour,
        timeStart: _timeObjectForHour(linkedHour, start: true),
        timeEnd: _timeObjectForHour(linkedHour, start: false),
        timeToEnd: _timeObjectForHour(linkedHour, start: false),
        teachers: teachers,
        linkToPreviousHour: 1,
      ),
  ];

  return {
    date: {
      '0': {
        '0': {
          '3': {
            'isLesson': 1,
            'lesson': _lessonPayload(
              date: date,
              hour: hour,
              toHour: toHour,
              timeStart: _timeObjectForHour(hour, start: true),
              timeEnd: _timeObjectForHour(hour, start: false),
              timeToEnd: _timeObjectForHour(toHour, start: false),
              teachers: teachers,
              linkedHours: linkedHours,
            ),
            'hour': hour,
            'linkedHoursCount': linkedHours.length,
          },
        },
      },
    },
  };
}

CalendarLoadedPayload _calendarLoaded(Map<String, dynamic> data) {
  return CalendarLoadedPayload(
    data: data,
    config: _substituteDetectionConfig(
      primaryTeachers: const <String, BuiltList<String>>{},
      lockedSubjects: const <String>[],
    ),
  );
}

Future<void> _recalculateSubstitutesFromState(
  Store<AppState, AppStateBuilder, AppActions> store,
) async {
  await store.actions.calendarActions.recalculateSubstitutes(
    _substituteDetectionConfig(
      enabled: store.state.settingsState.substituteDetectionEnabled,
      primaryTeachers:
          store.state.settingsState.substitutePrimaryTeachers.toMap(),
      lockedSubjects: store
          .state.settingsState.substitutePrimaryTeachersLockedSubjects
          .toList(),
    ),
  );
}

Future<void> _flushAsyncActions() {
  return Future<void>.delayed(const Duration(milliseconds: 10));
}

Future<void> _runAutoPopulatePrimaryTeachersTest(
  Store<AppState, AppStateBuilder, AppActions> store,
) async {
  await store.actions.calendarActions.loaded(
    _calendarLoaded(_calendarPayloadForDate(
      date: '2026-04-03',
      teacherFirstName: 'Christoph',
      teacherLastName: 'Holzer',
    )),
  );
  await store.actions.calendarActions.loaded(
    _calendarLoaded(_calendarPayloadForDate(
      date: '2026-04-10',
      teacherFirstName: 'Christoph',
      teacherLastName: 'Holzer',
    )),
  );
  await store.actions.calendarActions.loaded(
    _calendarLoaded(_calendarPayloadForDate(
      date: '2026-04-17',
      teacherFirstName: 'Doris',
      teacherLastName: 'Hilpold',
    )),
  );
  await _flushAsyncActions();

  expect(
    store.state.settingsState.substitutePrimaryTeachers['Informatik'],
    BuiltList<String>(const <String>['Christoph Holzer']),
  );
}

SubstituteDetectionConfig _substituteDetectionConfig({
  bool enabled = true,
  required Map<String, BuiltList<String>> primaryTeachers,
  required List<String> lockedSubjects,
}) {
  return SubstituteDetectionConfig(
    (b) => b
      ..enabled = enabled
      ..primaryTeachers = MapBuilder<String, BuiltList<String>>(primaryTeachers)
      ..lockedSubjects = ListBuilder<String>(lockedSubjects),
  );
}

Map<String, dynamic> _lessonPayload({
  required String date,
  required int hour,
  required int toHour,
  required Map<String, Object> timeStart,
  required Map<String, Object> timeEnd,
  required Map<String, Object> timeToEnd,
  required List<Map<String, dynamic>> teachers,
  List<Map<String, dynamic>> linkedHours = const [],
  int linkToPreviousHour = 0,
}) {
  return {
    'id': hour == toHour ? 26294 + hour : null,
    'ttcid': 1113581 + hour,
    'date': date,
    'hour': hour,
    'toHour': toHour,
    'timeStartObject': timeStart,
    'timeEndObject': timeEnd,
    'timeToEndObject': timeToEnd,
    'classId': 120,
    'className': '5AT',
    'teachers': teachers,
    'teachersToNotify': [],
    'teacherMyself': null,
    'subject': {
      'id': 16,
      'name': 'Informatik',
    },
    'homeworkExams': [],
    'lessonContents': [],
    'rooms': [
      {
        'id': 5,
        'name': 'PC 1',
      }
    ],
    'readOnly': true,
    'isSubstitute': 0,
    'linkToPreviousHour': linkToPreviousHour,
    'linkedHours': linkedHours,
  };
}

Map<String, Object> _timeObjectForHour(int hour, {required bool start}) {
  const baseStartMinutes = 9 * 60 + 35;
  const lessonLengthMinutes = 50;
  final totalMinutes =
      baseStartMinutes + ((hour - 3) * lessonLengthMinutes) + (start ? 0 : 50);
  final hours = (totalMinutes ~/ 60).toString().padLeft(2, '0');
  final minutes = (totalMinutes % 60).toString().padLeft(2, '0');
  return {
    'h': hours,
    'm': minutes,
    'ts': totalMinutes * 60,
    'text': '$hours:$minutes',
    'html': '$hours<sup>$minutes</sup>',
  };
}

final Map<String, Object?> absencesJson = <String, Object?>{
  'absences': <Object>[
    <String, Object?>{
      'group': <Object>[
        <String, Object?>{
          'id': 3044,
          'minutes': 50,
          'minutes_begin': 0,
          'minutes_end': 0,
          'date': '2021-02-02',
          'hour': 5,
        },
        <String, Object?>{
          'id': 3032,
          'minutes': 50,
          'minutes_begin': 0,
          'minutes_end': 0,
          'date': '2021-02-02',
          'hour': 4,
        },
        <String, Object?>{
          'id': 3026,
          'minutes': 50,
          'minutes_begin': 0,
          'minutes_end': 0,
          'date': '2021-02-02',
          'hour': 3,
        },
        <String, Object?>{
          'id': 3012,
          'minutes': 50,
          'minutes_begin': 0,
          'minutes_end': 0,
          'date': '2021-02-02',
          'hour': 2,
        },
      ],
      'date': '2021-02-02',
      'note': null,
      'reason': 'Laura ist noch immer nicht ganz fit',
      'reason_signature': null,
      'reason_timestamp': null,
      'reason_user': 1768,
      'justified': 1,
    },
    <String, Object?>{
      'group': <Object>[
        <String, Object?>{
          'id': 2985,
          'minutes': 50,
          'minutes_begin': 0,
          'minutes_end': 0,
          'date': '2021-02-01',
          'hour': 5,
        },
        <String, Object?>{
          'id': 3002,
          'minutes': 50,
          'minutes_begin': 0,
          'minutes_end': 0,
          'date': '2021-02-01',
          'hour': 4,
        },
      ],
      'date': '2021-02-01',
      'note': null,
      'reason':
          'Laura fühlt sich nicht ganz wohl, sie bleibt sicherheitshalber zu Hause',
      'reason_signature': null,
      'reason_timestamp': null,
      'reason_user': 1768,
      'justified': 1,
    },
  ],
  'futureAbsences': <Object>[],
  'canEdit': true,
  'statistics': <String, Object?>{
    'counter': '',
    'counterForSchool': '',
    'percentage': '',
    'justified': 0,
    'notJustified': 0,
    'delayed': 0,
  },
};

final Map<String, dynamic> calendarPageOne = <String, dynamic>{
  '2022-09-28': <String, Object?>{
    '1': <String, Object?>{
      '1': <String, Object?>{
        '1': <String, Object?>{
          'isLesson': 1,
          'hour': 1,
          'lesson': <String, Object?>{
            'hour': 1,
            'toHour': 2,
            'date': '2022-09-28',
            'subject': <String, Object?>{'name': 'Projekttag'},
            'teachers': <Object>[
              <String, Object?>{'firstName': 'Tom', 'lastName': 'Smith'},
            ],
            'rooms': <Object>[],
            'homeworkExams': <Object>[
              <String, Object?>{
                'deadline': '2022-09-28',
                'hasGradeGroupSubmissions': false,
                'hasGrades': false,
                'homework': 1,
                'id': 5,
                'name': 'Arbeitsblatt',
                'online': false,
                'typeId': 500,
                'typeName': 'Hausaufgabe',
              },
            ],
            'lessonContents': <Object>[],
            'timeStartObject': <String, Object?>{'h': '07', 'm': '40'},
            'timeEndObject': <String, Object?>{'h': '08', 'm': '35'},
            'linkedHours': <Object>[
              <String, Object?>{
                'date': '2022-09-28',
                'timeStartObject': <String, Object?>{'h': '08', 'm': '35'},
                'timeEndObject': <String, Object?>{'h': '09', 'm': '25'},
              },
            ],
          },
        },
      },
    },
  },
};

final Map<String, dynamic> calendarPageTwo = <String, dynamic>{
  '2022-09-29': <String, Object?>{
    '1': <String, Object?>{
      '1': <String, Object?>{
        '1': <String, Object?>{
          'isLesson': 1,
          'hour': 3,
          'lesson': <String, Object?>{
            'hour': 3,
            'toHour': 3,
            'date': '2022-09-29',
            'subject': <String, Object?>{'name': 'Mathematik'},
            'teachers': <Object>[
              <String, Object?>{'firstName': 'Anna', 'lastName': 'Rossi'},
            ],
            'rooms': <Object>[
              <String, Object?>{'name': 'Raum 2'},
            ],
            'homeworkExams': <Object>[],
            'lessonContents': <Object>[],
            'timeStartObject': <String, Object?>{'h': '10', 'm': '15'},
            'timeEndObject': <String, Object?>{'h': '11', 'm': '05'},
            'linkedHours': <Object>[],
          },
        },
      },
    },
  },
};

final Map<String, Object?> subjectsPayload = <String, Object?>{
  'subjects': <Object>[
    <String, Object?>{
      'subject': <String, Object?>{'id': 1, 'name': 'Deutsch'},
      'grades': <Object>[
        <String, Object?>{
          'grade': '7.50',
          'weight': 100,
          'date': '2021-02-03',
          'cancelled': 0,
          'type': 'Schularbeit',
        },
      ],
    },
    <String, Object?>{
      'subject': <String, Object?>{'id': 2, 'name': 'Mathematik'},
      'grades': <Object>[],
    },
  ],
};

final Map<String, Object?> subjectDetailsPayload = <String, Object?>{
  'grades': <Object>[
    <String, Object?>{
      'id': 12,
      'grade': '7.50',
      'weight': 100,
      'date': '2021-02-03',
      'cancelled': false,
      'typeName': 'Schularbeit',
      'created': 'am 4. 2. erstellt',
      'name': 'Schularbeit 1',
      'description': 'Kapitel 1',
      'competences': <Object>[
        <String, Object?>{
          'typeName': 'Textverständnis',
          'grade': '4',
        },
      ],
    },
  ],
  'observations': <Object>[
    <String, Object?>{
      'typeName': 'Beobachtung',
      'cancelled': 0,
      'created': 'Am 5. März 2021',
      'note': 'Gut vorbereitet',
      'date': '2021-03-05',
    },
  ],
};

final Map<String, Object?> profilePayload = <String, Object?>{
  'name': 'Debertol Michael',
  'codiceFiscale': 'BCCTBS07S23B220B',
  'email': 'st-debmic-03@vinzentinum.it',
  'picture': '2GSwZUaN5CTXPPtHMcNEXGwq4rWqvFxA',
  'username': 'st-debmic-03',
  'roleName': 'Schüler/in',
  'notificationsEnabled': false,
};
