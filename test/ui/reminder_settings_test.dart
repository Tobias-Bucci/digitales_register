import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/reminder_notifications.dart';
import 'package:dr/ui/reminder_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Holds the settings like the store does.
class _Host extends StatefulWidget {
  const _Host({
    required this.service,
    this.enabled = false,
    this.assessments = false,
  });
  final ReminderNotificationService service;
  final bool enabled;
  final bool assessments;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  static String savedUrl = '';

  late bool enabled = widget.enabled;
  late bool assessments = widget.assessments;
  int minute = 7 * 60 + 30;
  List<int> weekdays = [1, 2, 3, 4, 5];
  List<int> days = [3, 2, 1];
  int assessmentMinute = 18 * 60;
  bool exams = true;
  bool tests = true;
  bool homework = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReminderSettings(
              service: widget.service,
              mensaEnabled: enabled,
              mensaMinuteOfDay: minute,
              mensaUrl: savedUrl,
              onSetMensaEnabled: (value) => setState(() => enabled = value),
              onSetMensaMinuteOfDay: (value) => setState(() => minute = value),
              onSetMensaUrl: (value) => setState(() => savedUrl = value),
              mensaWeekdays: weekdays,
              onSetMensaWeekdays: (value) => setState(() => weekdays = value),
              assessmentsEnabled: assessments,
              assessmentDays: days,
              onSetAssessmentsEnabled: (value) =>
                  setState(() => assessments = value),
              examsEnabled: exams,
              onSetExamsEnabled: (value) => setState(() => exams = value),
              testsEnabled: tests,
              onSetTestsEnabled: (value) => setState(() => tests = value),
              homeworkEnabled: homework,
              onSetHomeworkEnabled: (value) => setState(() => homework = value),
              onSetAssessmentDays: (value) => setState(() => days = value),
              assessmentMinuteOfDay: assessmentMinute,
              onSetAssessmentMinuteOfDay: (value) =>
                  setState(() => assessmentMinute = value),
            ),
          ),
        ),
      );
}

void main() {
  var granted = true;
  var requests = 0;

  ReminderNotificationService service({
    ReminderBackend backend = ReminderBackend.systemRepeating,
  }) =>
      ReminderNotificationService(
        backend: backend,
        initializer: () async {},
        permission: () async => granted,
        permissionRequest: () async {
          requests++;
          return granted;
        },
      );

  setUp(() {
    granted = true;
    requests = 0;
  });

  Future<void> pump(WidgetTester tester, Widget host) async {
    // The card is taller than the default 800x600 test view; tests that size
    // the view themselves keep their size.
    if (tester.view.physicalSize == const Size(2400, 1800)) {
      tester.view.physicalSize = const Size(2400, 4800);
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(host);
    await tester.pumpAndSettle();
  }

  group('link of the mensa reminder', () {
    final field = find.byKey(const Key('mensa-reminder-url-field'));

    Future<void> enter(WidgetTester tester, String text) async {
      await tester.enterText(field, text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    setUp(() => _HostState.savedUrl = '');

    testWidgets('can only be edited while the reminder is on', (tester) async {
      await pump(tester, _Host(service: service()));
      expect(field, findsNothing);

      await tester.tap(find.byKey(const Key('mensa-reminder-toggle')));
      await tester.pumpAndSettle();

      expect(field, findsOneWidget);
    });

    testWidgets('saves a valid link and completes it', (tester) async {
      await pump(tester, _Host(service: service(), enabled: true));

      await enter(tester, '  example.org/menu ');

      expect(_HostState.savedUrl, 'https://example.org/menu');
      expect(
        tester.widget<TextField>(field).controller!.text,
        'https://example.org/menu',
      );
      expect(find.textContaining('gültigen Link'), findsNothing);
    });

    testWidgets('rejects an invalid link and keeps the last valid one',
        (tester) async {
      _HostState.savedUrl = 'https://example.org';
      await pump(tester, _Host(service: service(), enabled: true));

      await enter(tester, 'javascript:alert(1)');

      expect(_HostState.savedUrl, 'https://example.org');
      expect(find.textContaining('gültigen Link'), findsOneWidget);

      await tester.enterText(field, 'example');
      await tester.pump();
      expect(find.textContaining('gültigen Link'), findsNothing);
    });

    testWidgets('an empty field removes the link', (tester) async {
      _HostState.savedUrl = 'https://example.org';
      await pump(tester, _Host(service: service(), enabled: true));

      await enter(tester, '   ');

      expect(_HostState.savedUrl, isEmpty);
      expect(find.textContaining('gültigen Link'), findsNothing);
    });

    testWidgets('a link is not lost by leaving the page', (tester) async {
      await pump(tester, _Host(service: service(), enabled: true));

      await tester.enterText(field, 'example.org');
      await tester.pumpWidget(const SizedBox());

      expect(_HostState.savedUrl, 'https://example.org');
    });
  });

  testWidgets('the time can only be chosen while the reminder is on',
      (tester) async {
    await pump(tester, _Host(service: service()));
    expect(find.byKey(const Key('mensa-reminder-time')), findsNothing);

    await tester.tap(find.byKey(const Key('mensa-reminder-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mensa-reminder-time')), findsOneWidget);
    expect(find.text('07:30'), findsOneWidget);
  });

  testWidgets('turning the reminder on asks for permission, off does not',
      (tester) async {
    await pump(tester, _Host(service: service()));

    await tester.tap(find.byKey(const Key('mensa-reminder-toggle')));
    await tester.pumpAndSettle();
    expect(requests, 1);

    await tester.tap(find.byKey(const Key('mensa-reminder-toggle')));
    await tester.pumpAndSettle();
    expect(requests, 1);
  });

  testWidgets('a denied permission keeps the setting and explains the way out',
      (tester) async {
    granted = false;
    await pump(tester, _Host(service: service()));

    await tester.tap(find.byKey(const Key('mensa-reminder-toggle')));
    await tester.pumpAndSettle();

    expect(find.textContaining('nicht erlaubt'), findsOneWidget);
    expect(find.byKey(const Key('mensa-reminder-time')), findsOneWidget);
  });

  testWidgets('no warning while no reminder is on', (tester) async {
    granted = false;
    await pump(tester, _Host(service: service()));

    expect(find.textContaining('nicht erlaubt'), findsNothing);
  });

  testWidgets('the warning goes away after allowing it in the system',
      (tester) async {
    granted = false;
    await pump(tester, _Host(service: service(), enabled: true));
    expect(find.textContaining('nicht erlaubt'), findsOneWidget);

    granted = true;
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();

    expect(find.textContaining('nicht erlaubt'), findsNothing);
  });

  testWidgets('choosing a time saves it', (tester) async {
    await pump(tester, _Host(service: service(), enabled: true));

    await tester.tap(find.byKey(const Key('mensa-reminder-time')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '20');
    await tester.enterText(find.byType(TextFormField).last, '15');
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();

    expect(find.text('20:15'), findsOneWidget);
  });

  group('assessment reminders', () {
    const toggle = Key('assessment-reminder-toggle');
    const add = Key('assessment-reminder-add');
    const input = Key('assessment-reminder-day-input');
    const confirm = Key('assessment-reminder-day-confirm');
    Finder chip(int day) => find.byKey(Key('assessment-reminder-day-$day'));

    Future<void> addDay(WidgetTester tester, String day) async {
      await tester.tap(find.byKey(add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(input), day);
      await tester.tap(find.byKey(confirm));
      await tester.pumpAndSettle();
    }

    testWidgets('the days appear once the switch is on and it asks to notify',
        (tester) async {
      await pump(tester, _Host(service: service()));
      expect(chip(3), findsNothing);

      await tester.tap(find.byKey(toggle));
      await tester.pumpAndSettle();

      expect(requests, 1);
      expect(find.text('3 Tage vorher'), findsOneWidget);
      expect(find.text('2 Tage vorher'), findsOneWidget);
      expect(find.text('1 Tag vorher'), findsOneWidget);
      expect(find.textContaining('18:00'), findsOneWidget);
    });

    testWidgets('the time can only be chosen while the reminders are on',
        (tester) async {
      await pump(tester, _Host(service: service()));
      expect(find.byKey(const Key('assessment-reminder-time')), findsNothing);

      await tester.tap(find.byKey(toggle));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('assessment-reminder-time')), findsOneWidget);
    });

    testWidgets('choosing a time saves it, apart from the Mensa time',
        (tester) async {
      await pump(
        tester,
        _Host(service: service(), enabled: true, assessments: true),
      );

      await tester.tap(find.byKey(const Key('assessment-reminder-time')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '16');
      await tester.enterText(find.byType(TextFormField).last, '45');
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();

      expect(find.text('16:45'), findsOneWidget);
      expect(find.text('07:30'), findsOneWidget);
    });

    testWidgets('a day can be added and is sorted in', (tester) async {
      await pump(tester, _Host(service: service(), assessments: true));

      await addDay(tester, '7');

      expect(chip(7), findsOneWidget);
      expect(
        tester.getTopLeft(chip(7)).dx,
        lessThan(tester.getTopLeft(chip(3)).dx),
      );
    });

    testWidgets('a duplicate is explained and not added', (tester) async {
      await pump(tester, _Host(service: service(), assessments: true));

      await addDay(tester, '2');

      expect(find.text('Dieser Tag ist schon eingetragen.'), findsOneWidget);
      expect(find.byKey(input), findsOneWidget);
    });

    testWidgets('invalid days are explained and not added', (tester) async {
      await pump(tester, _Host(service: service(), assessments: true));

      await addDay(tester, '0');
      expect(find.text('Gib eine ganze Zahl ab 1 ein.'), findsOneWidget);

      await tester.enterText(find.byKey(input), '31');
      await tester.tap(find.byKey(confirm));
      await tester.pumpAndSettle();
      expect(find.text('Höchstens 30 Tage vorher.'), findsOneWidget);
    });

    testWidgets('the field only takes digits', (tester) async {
      await pump(tester, _Host(service: service(), assessments: true));
      await tester.tap(find.byKey(add));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(input), '-1.5a');

      expect(tester.widget<TextField>(find.byKey(input)).controller!.text, '15');
    });

    testWidgets('a day can be removed, but not the last one', (tester) async {
      await pump(tester, _Host(service: service(), assessments: true));

      for (final day in [3, 2]) {
        await tester.tap(
          find.descendant(of: chip(day), matching: find.byTooltip('Tag entfernen')),
        );
        await tester.pumpAndSettle();
        expect(chip(day), findsNothing);
      }

      expect(tester.widget<InputChip>(chip(1)).onDeleted, isNull);
    });

    testWidgets('no more days can be added at the limit', (tester) async {
      await pump(tester, _Host(service: service(), assessments: true));

      for (final day in [4, 5, 6, 7, 8, 9, 10]) {
        await addDay(tester, '$day');
      }

      expect(find.byKey(add), findsNothing);
    });

    testWidgets('the layout fits a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(320, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(tester, _Host(service: service(), assessments: true));
      await addDay(tester, '14');

      expect(tester.takeException(), isNull);
    });
  });

  group('weekdays of the mensa reminder', () {
    Finder day(int weekday) =>
        find.byKey(Key('mensa-reminder-weekday-$weekday'));
    List<int> saved(WidgetTester tester) =>
        tester.state<_HostState>(find.byType(_Host)).weekdays;

    testWidgets('Monday to Friday by default, in German, Monday first',
        (tester) async {
      await pump(tester, _Host(service: service(), enabled: true));

      for (final weekday in [1, 2, 3, 4, 5, 6, 7]) {
        expect(tester.widget<FilterChip>(day(weekday)).selected, weekday <= 5,
            reason: '$weekday');
      }
      expect(find.text('Mo'), findsOneWidget);
      expect(find.text('So'), findsOneWidget);
      expect(tester.getTopLeft(day(1)).dx,
          lessThan(tester.getTopLeft(day(2)).dx));
    });

    testWidgets('are only shown while the reminder is on', (tester) async {
      await pump(tester, _Host(service: service()));

      expect(day(1), findsNothing);
    });

    testWidgets('a tap adds or removes a day', (tester) async {
      await pump(tester, _Host(service: service(), enabled: true));

      await tester.tap(day(6));
      await tester.pumpAndSettle();
      expect(saved(tester), [1, 2, 3, 4, 5, 6]);

      await tester.tap(day(1));
      await tester.pumpAndSettle();
      expect(saved(tester), [2, 3, 4, 5, 6]);
    });

    testWidgets('the last day cannot be deselected, and it says why',
        (tester) async {
      await pump(tester, _Host(service: service(), enabled: true));
      final hint = find.byKey(const Key('mensa-reminder-weekdays-last'));
      expect(hint, findsNothing);

      for (final weekday in [1, 2, 3, 4]) {
        await tester.tap(day(weekday));
        await tester.pumpAndSettle();
      }

      expect(saved(tester), [5]);
      expect(tester.widget<FilterChip>(day(5)).onSelected, isNull);
      expect(hint, findsOneWidget);

      await tester.tap(day(5), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(saved(tester), [5]);

      // Another day makes it free again.
      await tester.tap(day(1));
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(day(5)).onSelected, isNotNull);
      expect(hint, findsNothing);
    });

    testWidgets('are announced with the full name and their state',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, _Host(service: service(), enabled: true));

      expect(
        tester.getSemantics(find.descendant(
          of: day(1),
          matching: find.byType(Semantics),
        ).first),
        matchesSemantics(
          label: 'Montag',
          isSelected: true,
          hasSelectedState: true,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      expect(find.bySemanticsLabel('Samstag'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('what the assessment reminders cover', () {
    const exam = Key('exam-reminder-toggle');
    const test = Key('test-reminder-toggle');
    const homework = Key('homework-reminder-toggle');
    const nothing = Key('assessment-reminder-nothing');
    _HostState host(WidgetTester tester) =>
        tester.state<_HostState>(find.byType(_Host));

    testWidgets('three switches below the main one, homework off',
        (tester) async {
      await pump(tester, _Host(service: service()));
      expect(find.byKey(exam), findsNothing);

      await tester.tap(find.byKey(const Key('assessment-reminder-toggle')));
      await tester.pumpAndSettle();

      expect(find.text('Schularbeiten und Prüfungen'), findsOneWidget);
      expect(find.text('Tests'), findsOneWidget);
      expect(find.text('Hausaufgaben'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(exam)).value, isTrue);
      expect(tester.widget<SwitchListTile>(find.byKey(test)).value, isTrue);
      expect(
          tester.widget<SwitchListTile>(find.byKey(homework)).value, isFalse);
    });

    testWidgets('each switch saves on its own', (tester) async {
      await pump(tester, _Host(service: service(), assessments: true));

      await tester.tap(find.byKey(homework));
      await tester.pumpAndSettle();
      expect((host(tester).exams, host(tester).tests, host(tester).homework),
          (true, true, true));

      await tester.tap(find.byKey(exam));
      await tester.pumpAndSettle();
      expect((host(tester).exams, host(tester).tests, host(tester).homework),
          (false, true, true));

      await tester.tap(find.byKey(test));
      await tester.pumpAndSettle();
      expect((host(tester).exams, host(tester).tests, host(tester).homework),
          (false, false, true));
    });

    testWidgets('the days before only matter for exams and tests',
        (tester) async {
      await pump(tester, _Host(service: service(), assessments: true));
      await tester.tap(find.byKey(homework));
      await tester.tap(find.byKey(exam));
      await tester.tap(find.byKey(test));
      await tester.pumpAndSettle();

      expect(find.text('1 Tag vorher'), findsNothing);
      expect(find.byKey(const Key('assessment-reminder-time')), findsOneWidget);
    });

    testWidgets('nothing chosen is allowed, but obvious', (tester) async {
      await pump(tester, _Host(service: service(), assessments: true));
      expect(find.byKey(nothing), findsNothing);

      await tester.tap(find.byKey(exam));
      await tester.tap(find.byKey(test));
      await tester.pumpAndSettle();

      expect(find.byKey(nothing), findsOneWidget);
      expect(find.textContaining('Nichts ausgewählt'), findsOneWidget);
      expect(find.byKey(const Key('assessment-reminder-time')), findsNothing);
    });
  });

  testWidgets('everything fits 320 px with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 4000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pump(
      tester,
      _Host(service: service(), enabled: true, assessments: true),
    );
    await tester.tap(find.byKey(const Key('exam-reminder-toggle')));
    await tester.tap(find.byKey(const Key('test-reminder-toggle')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('says so where reminders need the app to be open',
      (tester) async {
    await pump(
      tester,
      _Host(service: service(backend: ReminderBackend.whileRunning)),
    );

    expect(find.textContaining('solange die App geöffnet ist'), findsOneWidget);
  });
}
