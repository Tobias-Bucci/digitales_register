import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:dr/actions/dashboard_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/main.dart' show RegisterApp, navigatorKey;
import 'package:dr/middleware/middleware.dart' show showLegacyStudyDataDialog;
import 'package:dr/school_notification_engine.dart';
import 'package:dr/school_notification_service.dart';
import 'package:dr/study_data_migration.dart';
import 'package:dr/ui/compact_day_list.dart';
import 'package:dr/ui/days.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/school_notification_opt_in.dart';
import 'package:dr/ui/sidebar.dart' show confirmRemoveAccount;
import 'package:dr/ui/system_pages.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/test_harness.dart';

const _phone = Size(360, 640);
const _wide = Size(1280, 800);

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

AppState _state({String language = 'de'}) =>
    AppState((b) => b.settingsState.languageCode = language);

/// Pumps an app whose first page opens [page] on the root navigator, as the
/// middleware does.
Future<void> _pumpSystemPage(
  WidgetTester tester,
  Widget page, {
  bool newDesign = true,
  Size size = _phone,
  String language = 'de',
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1,
}) async {
  _size(tester, size);
  final store = createStore(
    initialState: _state(language: language),
    newDesign: newDesign,
  );
  await pumpApp(
    tester,
    store: store,
    themeMode: themeMode,
    home: const Scaffold(body: Text('home')),
  );
  unawaited(
    tester.state<NavigatorState>(find.byType(Navigator).first).push(
          MaterialPageRoute<void>(
            builder: (_) => MediaQuery.withClampedTextScaling(
              minScaleFactor: textScale,
              maxScaleFactor: textScale,
              child: page,
            ),
          ),
        ),
  );
  await settleFor(tester, duration: const Duration(milliseconds: 600));
}

class _Service extends SchoolNotificationService {
  int saves = 0;
  _Service() {
    activeAccount = notificationDigest(['school', 'student']);
    activeAccountLabel = 'Student · school.example';
  }
  @override
  int get sessionGeneration => 1;
  @override
  Future<SchoolNotificationOptInOffer?> pendingOptIn() async =>
      preferences.consent == SchoolNotificationConsent.unknown
          ? SchoolNotificationOptInOffer(activeAccount!, 1, activeAccountLabel!)
          : null;
  @override
  Future<bool> decideOptIn(SchoolNotificationOptInOffer offer,
      {required bool accept, bool grades = true, bool messages = true}) async {
    saves++;
    preferences
      ..consent = accept
          ? SchoolNotificationConsent.accepted
          : SchoolNotificationConsent.declined
      ..enabled = accept
      ..grades = grades
      ..messages = messages;
    notifyListeners();
    return true;
  }
}

/// A day the dashboard shows whenever the test runs: it lists the days from
/// today on.
final _today = () {
  final tomorrow = DateTime.now().add(const Duration(days: 1));
  return UtcDateTime(tomorrow.year, tomorrow.month, tomorrow.day);
}();

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  group('the choice of the design', () {
    Future<bool> chosen(WidgetTester tester, {required bool newDesign}) async {
      late bool result;
      await pumpApp(
        tester,
        store: createStore(newDesign: newDesign),
        home: Builder(builder: (context) {
          result = newDesignChosen(context);
          return const SizedBox();
        }),
      );
      return result;
    }

    testWidgets('follows the setting', (tester) async {
      expect(await chosen(tester, newDesign: true), isTrue);
      expect(await chosen(tester, newDesign: false), isFalse);
    });

    testWidgets('is Legacy without a store', (tester) async {
      late bool result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        result = newDesignChosen(context);
        return const SizedBox();
      })));
      expect(result, isFalse);
    });
  });

  group('error page', () {
    testWidgets('the new design shows a state card in the page frame',
        (tester) async {
      var contacted = 0;
      await _pumpSystemPage(
        tester,
        ErrorPage(messageKey: 'error.parse', onContact: () => contacted++),
      );

      expect(find.byKey(const Key('error-page-new')), findsOneWidget);
      expect(find.byType(GlassStateCard), findsOneWidget);
      expect(find.byKey(const Key('system-page-header')), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Fehler!'), findsOneWidget);
      expect(
        find.text('Die Registerdaten konnten nicht gelesen werden. Bitte '
            'versuche es erneut oder kontaktiere den Entwickler.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Entwickler benachrichtigen'));
      expect(contacted, 1);

      await tester.tap(find.byType(BackButton));
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(find.byType(ErrorPage), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('Legacy keeps the red bar', (tester) async {
      var contacted = 0;
      await _pumpSystemPage(
        tester,
        ErrorPage(messageKey: 'error.session', onContact: () => contacted++),
        newDesign: false,
      );

      expect(find.byType(GlassStateCard), findsNothing);
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.backgroundColor, Colors.red);
      expect(find.text('Fehler!'), findsOneWidget);
      expect(
          find.textContaining('Die Sitzung ist abgelaufen.'), findsOneWidget);
      await tester.tap(
          find.widgetWithText(ElevatedButton, 'Entwickler benachrichtigen'));
      expect(contacted, 1);
    });
  });

  group('unsupported user type', () {
    testWidgets('the new design offers the website and a way back',
        (tester) async {
      var opened = 0;
      await _pumpSystemPage(
        tester,
        UserTypeUnsupportedPage(onOpenWebsite: () => opened++),
      );

      expect(find.byKey(const Key('user-type-unsupported-page-new')), findsOne);
      expect(find.text('Tut uns leid!'), findsOneWidget);
      expect(
        find.text('Diese App ist ausschließlich für Schüler*innen und Eltern '
            'geeignet.'),
        findsOneWidget,
      );
      await tester.tap(find.text("Hier geht's zur Website"));
      expect(opened, 1);

      await tester.tap(find.text('Abbrechen'));
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(find.byType(UserTypeUnsupportedPage), findsNothing);
    });

    testWidgets('Legacy keeps its plain page', (tester) async {
      await _pumpSystemPage(
        tester,
        UserTypeUnsupportedPage(onOpenWebsite: () {}),
        newDesign: false,
        // The test font is too wide for the row of buttons of a phone.
        size: _wide,
      );

      expect(find.byType(GlassStateCard), findsNothing);
      expect(find.widgetWithText(ElevatedButton, "Hier geht's zur Website"),
          findsOneWidget);
    });
  });

  group('unknown route', () {
    testWidgets('the new design names the route and leads home',
        (tester) async {
      _size(tester, _phone);
      await pumpApp(
        tester,
        store: createStore(initialState: _state(), newDesign: true),
        home: const Scaffold(body: Text('home')),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => settings.name == '/'
              ? const Scaffold(body: Text('home'))
              : UnknownRoutePage(routeName: settings.name ?? ''),
        ),
      );
      unawaited(tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .pushNamed('/old-link'));
      await settleFor(tester, duration: const Duration(milliseconds: 600));

      expect(find.byKey(const Key('unknown-route-page-new')), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Seite nicht gefunden'), findsOneWidget);
      expect(find.textContaining('/old-link'), findsOneWidget);

      await tester.tap(find.text('Zur Startseite'));
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(find.byType(UnknownRoutePage), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('Legacy keeps its bar', (tester) async {
      await _pumpSystemPage(
        tester,
        const UnknownRoutePage(routeName: '/old-link'),
        newDesign: false,
      );
      expect(find.byType(GlassStateCard), findsNothing);
      expect(
          find.widgetWithText(AppBar, 'Seite nicht gefunden'), findsOneWidget);
    });
  });

  group('unknown route in the app', () {
    for (final newDesign in [true, false]) {
      testWidgets(
          'the routes of the app open the page '
          '${newDesign ? 'in the new design' : 'in Legacy'}', (tester) async {
        _size(tester, _phone);
        await tester.pumpWidget(RegisterApp(
          store: createStore(initialState: _state(), newDesign: newDesign),
        ));
        await tester.pump();
        unawaited(navigatorKey!.currentState!.pushNamed('/no-such-page'));
        await settleFor(tester, duration: const Duration(milliseconds: 600));

        expect(find.byType(UnknownRoutePage), findsOneWidget);
        expect(find.textContaining('/no-such-page'), findsOneWidget);
        expect(find.byKey(const Key('unknown-route-page-new')),
            newDesign ? findsOneWidget : findsNothing);
        expect(find.byType(GlassStateCard),
            newDesign ? findsOneWidget : findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 6));
      });
    }
  });

  group('system pages in the new design', () {
    final pages = <String, Widget>{
      'error': ErrorPage(messageKey: 'error.generic', onContact: () {}),
      'unsupported': UserTypeUnsupportedPage(onOpenWebsite: () {}),
      'unknown': const UnknownRoutePage(routeName: '/x'),
    };

    for (final MapEntry(key: name, value: page) in pages.entries) {
      testWidgets('$name has blur only in its header', (tester) async {
        await _pumpSystemPage(tester, page);
        final header = find.byKey(const Key('system-page-header'));
        expect(find.byType(BackdropFilter), findsWidgets);
        expect(
          find.descendant(of: header, matching: find.byType(BackdropFilter)),
          findsNWidgets(find.byType(BackdropFilter).evaluate().length),
        );
      });

      for (final size in [_phone, _wide]) {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          testWidgets('$name fits $size in ${mode.name}', (tester) async {
            await _pumpSystemPage(tester, page, size: size, themeMode: mode);
            expect(find.byType(GlassStateCard), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        }
      }

      testWidgets('$name fits 320 px with text at 200 %', (tester) async {
        await _pumpSystemPage(
          tester,
          page,
          size: const Size(320, 640),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('$name keeps working in high contrast', (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(highContrast: true);
        addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await _pumpSystemPage(tester, page);
        expect(find.byType(GlassStateCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      for (final language in ['de', 'it', 'en', 'lld']) {
        testWidgets('$name is translated into $language', (tester) async {
          await _pumpSystemPage(tester, page, language: language);
          expect(find.textContaining('error.'), findsNothing);
          expect(find.textContaining('login.'), findsNothing);
          expect(find.textContaining('navigation.'), findsNothing);
          expect(find.textContaining('common.'), findsNothing);
        });
      }
    }
  });

  group('school notification opt-in', () {
    Future<_Service> host(WidgetTester tester, {Size size = _phone}) async {
      _size(tester, size);
      final service = _Service();
      addTearDown(service.dispose);
      await pumpApp(
        tester,
        store: createStore(initialState: _state(), newDesign: true),
        home: SchoolNotificationOptInHost(
          signedIn: true,
          account: service.activeAccount,
          service: service,
          ready: ValueNotifier(true),
          child: const Scaffold(body: Text('Dashboard')),
        ),
      );
      await tester.pumpAndSettle();
      return service;
    }

    testWidgets('is a glass sheet in the new design on phones', (tester) async {
      await host(tester);
      expect(find.byType(SchoolNotificationOptInDialog), findsOneWidget);
      expect(find.byType(GlassSheet), findsOneWidget);
      expect(find.byType(GlassPanel), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Neuigkeiten aus der Schule?'), findsOneWidget);
      expect(find.text('Student · school.example'), findsOneWidget);
    });

    testWidgets('is a centred panel in wide windows', (tester) async {
      await host(tester, size: _wide);
      expect(find.byType(GlassSheet), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('cannot be closed without an answer', (tester) async {
      final service = await host(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SchoolNotificationOptInDialog), findsOneWidget);
      expect(service.saves, 0);
    });

    testWidgets('stores the same choices', (tester) async {
      final service = await host(tester);
      await tester.tap(find.byType(CheckboxListTile).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(service.saves, 1);
      expect(service.preferences.enabled, isTrue);
      expect(service.preferences.grades, isTrue);
      expect(service.preferences.messages, isFalse);
      expect(find.byType(SchoolNotificationOptInDialog), findsNothing);
    });

    testWidgets('declining stays off', (tester) async {
      final service = await host(tester);
      final decline = find.text('Nein, danke');
      final accept = find.text('Benachrichtigungen aktivieren');
      // Decline first, as in the dialog: before it in the line, or above it
      // where the line is too narrow for both.
      final first = tester.getCenter(decline),
          second = tester.getCenter(accept);
      expect(first.dx < second.dx || first.dy < second.dy, isTrue);
      await tester.ensureVisible(decline);
      await tester.pumpAndSettle();
      await tester.tap(decline);
      await tester.pumpAndSettle();
      expect(service.saves, 1);
      expect(service.preferences.enabled, isFalse);
    });
  });

  group('older study notes', () {
    const summary = LegacyStudySummary(exams: 1, notes: 1, files: 1);

    Future<List<String>> show(WidgetTester tester, {Size size = _phone}) async {
      _size(tester, size);
      final store = createStore(initialState: _state(), newDesign: true);
      final dispatched = <String>[];
      store.actions.assignLegacyStudyData
          .setDispatcher((action) => dispatched.add(action.name));
      store.actions.discardLegacyStudyData
          .setDispatcher((action) => dispatched.add(action.name));
      await pumpApp(tester,
          store: store, home: const Scaffold(body: Text('home')));
      unawaited(showLegacyStudyDataDialog(store.actions, summary));
      await tester.pumpAndSettle();
      return dispatched;
    }

    testWidgets('are asked about in a glass sheet', (tester) async {
      await show(tester);
      expect(find.byType(GlassSheet), findsOneWidget);
      expect(find.text('Ältere Lerndaten ohne Konto'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      for (final answer in ['Verwerfen …', 'Diesem Konto zuordnen', 'Später']) {
        expect(find.text(answer), findsOneWidget);
      }
    });

    testWidgets('assigning dispatches the assignment', (tester) async {
      final dispatched = await show(tester);
      await tester.tap(find.text('Diesem Konto zuordnen'));
      await tester.pumpAndSettle();
      expect(dispatched, ['AppActions-assignLegacyStudyData']);
    });

    testWidgets('closing the sheet keeps them', (tester) async {
      final dispatched = await show(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(GlassSheet), findsNothing);
      expect(dispatched, isEmpty);
    });

    testWidgets('discarding is confirmed in a dialog with the glass rim',
        (tester) async {
      final dispatched = await show(tester);
      await tester.tap(find.text('Verwerfen …'));
      await tester.pumpAndSettle();
      expect(find.text('Ältere Lerndaten endgültig löschen?'), findsOneWidget);
      final material = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Material),
      );
      expect(
          tester.widget<Material>(material.first).shape, isA<GlassRimBorder>());
      await tester.tap(find.text('Endgültig löschen'));
      await tester.pumpAndSettle();
      expect(dispatched, ['AppActions-discardLegacyStudyData']);
    });
  });

  group('dashboard dialogs', () {
    AppState dashboard({
      List<Homework> homework = const [],
      List<Homework> deleted = const [],
    }) =>
        AppState((b) {
          b.dashboardState.allDays = ListBuilder<Day>([
            buildDay(
                date: _today, homework: homework, deletedHomework: deleted),
          ]);
          b.notificationState.lastFetched = _today;
          b.loginState
            ..loggedIn = true
            ..username = 'anna';
          b.url = 'https://franziskanergymnasium.digitalesregister.it';
          b.settingsState
            ..languageCode = 'de'
            ..askWhenDelete = true;
          b.noInternet = false;
        });

    Future<({List<String> reminders, List<String> calls})> pumpDashboard(
      WidgetTester tester,
      AppState state, {
      Size size = const Size(412, 900),
    }) async {
      _size(tester, size);
      final store = createStore(initialState: state, newDesign: true);
      final reminders = <String>[];
      final calls = <String>[];
      store.actions.dashboardActions.addReminder.setDispatcher((action) =>
          reminders.add((action.payload as AddReminderPayload).msg));
      store.actions.dashboardActions.deleteHomework
          .setDispatcher((action) => calls.add('delete'));
      store.actions.settingsActions.askWhenDeleteReminder
          .setDispatcher((action) => calls.add('ask ${action.payload}'));
      await pumpApp(tester, store: store, home: DaysContainer());
      await settleFor(tester);
      return (reminders: reminders, calls: calls);
    }

    final addButton = find.byKey(ValueKey('day-add-entry-$_today'));

    testWidgets('a new entry is asked for in a glass sheet', (tester) async {
      final recorded = await pumpDashboard(tester, dashboard());
      await tester.tap(addButton);
      await settleFor(tester, duration: const Duration(milliseconds: 600));

      expect(find.byType(GlassSheet), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Erinnerung'), findsOneWidget);
      // The hint about the commands is shown the first time.
      expect(find.byType(GlassCard), findsWidgets);

      final save = find.widgetWithText(FilledButton, 'Speichern');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      // A command is completed by its chip.
      await tester.enterText(find.byType(TextField), '/te');
      await tester.pump();
      final chip = find.byType(ActionChip);
      expect(chip, findsWidgets);
      expect(tester.widget<ActionChip>(chip.first).mouseCursor,
          NewDesignTheme.clickCursor);
      await tester.tap(chip.first);
      await tester.pump();
      final text =
          tester.widget<TextField>(find.byType(TextField)).controller!.text;
      expect(text, startsWith('/test@'));

      await tester.enterText(find.byType(TextField), '/test@1 Proca');
      await tester.pump();
      await tester.tap(save);
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(find.byType(GlassSheet), findsNothing);
      expect(recorded.reminders, ['/test@1 Proca']);
    });

    testWidgets('cancelling a new entry stores nothing', (tester) async {
      final recorded = await pumpDashboard(tester, dashboard());
      await tester.tap(addButton);
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      await tester.enterText(find.byType(TextField), 'Buch');
      await tester.tap(find.text('Abbrechen'));
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(recorded.reminders, isEmpty);
    });

    testWidgets('the entry sheet is a panel in wide windows', (tester) async {
      await pumpDashboard(tester, dashboard(), size: _wide);
      await tester.tap(addButton);
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(find.byType(GlassSheet), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    final reminder = buildHomework(
      id: 7,
      title: 'Erinnerung',
      subtitle: 'Buch mitnehmen',
      type: HomeworkType.homework,
      deleteable: true,
      checkable: true,
    );

    Future<void> askToDelete(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('compact-row-open-7')));
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const Key('entry-details-delete')));
      await settleFor(tester, duration: const Duration(milliseconds: 600));
    }

    testWidgets('deleting is confirmed in a glass sheet', (tester) async {
      final recorded =
          await pumpDashboard(tester, dashboard(homework: [reminder]));
      await askToDelete(tester);

      expect(find.byType(GlassSheet), findsOneWidget);
      expect(find.text('Erinnerung löschen?'), findsOneWidget);
      expect(find.text('Nie fragen'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reminder-delete-confirm')));
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(recorded.calls, ['delete']);
    });

    testWidgets('"never ask" is stored before deleting', (tester) async {
      final recorded =
          await pumpDashboard(tester, dashboard(homework: [reminder]));
      await askToDelete(tester);
      await tester.tap(find.byKey(const Key('reminder-delete-never-ask')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reminder-delete-confirm')));
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(recorded.calls, ['ask false', 'delete']);
    });

    testWidgets('cancelling keeps the reminder', (tester) async {
      final recorded =
          await pumpDashboard(tester, dashboard(homework: [reminder]));
      await askToDelete(tester);
      await tester.tap(find.byKey(const Key('reminder-delete-never-ask')));
      await tester.tap(find.text('Abbrechen'));
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(recorded.calls, isEmpty);
    });

    testWidgets('deleted entries are listed in a glass sheet', (tester) async {
      await pumpDashboard(
        tester,
        dashboard(
          homework: [reminder],
          deleted: [
            buildHomework(id: 9, title: 'Hausaufgabe', subtitle: 'Weg'),
          ],
        ),
      );
      await tester.tap(find.byTooltip('Gelöschte Einträge'));
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(find.byType(GlassSheet), findsOneWidget);
      expect(
        find.descendant(
            of: find.byType(GlassPanel), matching: find.byType(ItemWidget)),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('removing an account stays a dialog with the glass rim',
        (tester) async {
      await pumpDashboard(tester, dashboard());
      unawaited(confirmRemoveAccount(
          tester.element(find.byType(CompactDayWidget)), 'anna'));
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      final material = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Material),
      );
      expect(
          tester.widget<Material>(material.first).shape, isA<GlassRimBorder>());
      expect(find.text('Konto entfernen'), findsOneWidget);
    });
  });
}
