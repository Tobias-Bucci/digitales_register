import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/reminder_notifications.dart';
import 'package:dr/ui/reminder_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Holds the settings like the store does.
class _Host extends StatefulWidget {
  const _Host({required this.service, this.enabled = false});
  final ReminderNotificationService service;
  final bool enabled;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool enabled = widget.enabled;
  int minute = 7 * 60 + 30;

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
    await tester.enterText(find.byType(TextFormField).first, '9');
    await tester.enterText(find.byType(TextFormField).last, '15');
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();

    expect(find.text('09:15'), findsOneWidget);
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
