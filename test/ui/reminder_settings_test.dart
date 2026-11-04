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
  late bool enabled = widget.enabled;
  late bool assessments = widget.assessments;
  int minute = 7 * 60 + 30;
  List<int> days = [3, 2, 1];
  int assessmentMinute = 18 * 60;

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
              onSetMensaEnabled: (value) => setState(() => enabled = value),
              onSetMensaMinuteOfDay: (value) => setState(() => minute = value),
              assessmentsEnabled: assessments,
              assessmentDays: days,
              onSetAssessmentsEnabled: (value) =>
                  setState(() => assessments = value),
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
    await tester.pumpWidget(host);
    await tester.pumpAndSettle();
  }

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
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(tester, _Host(service: service(), assessments: true));
      await addDay(tester, '14');

      expect(tester.takeException(), isNull);
    });
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
