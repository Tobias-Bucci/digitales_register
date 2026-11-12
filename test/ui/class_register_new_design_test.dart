import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/class_register_cache.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/extras_page_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/class_register_page.dart';
import 'package:dr/ui/class_register_page_new.dart';
import 'package:dr/ui/extras_page.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/readable_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

import '../support/test_harness.dart';

const _phone = Size(412, 900);

AppState _state({String languageCode = 'de'}) => AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.settingsState.languageCode = languageCode;
    });

ClassRegisterLesson _lesson(
  String date,
  int hour,
  String subject, {
  bool open = false,
  bool substitute = false,
  List<String> contents = const [],
}) =>
    ClassRegisterLesson.fromJson({
      'date': date,
      'hour': hour,
      'toHour': hour,
      'timeStart': 27000 + hour * 3000,
      'timeEnd': 30000 + hour * 3000,
      'className': '5AT',
      'subject': {'name': subject},
      'lessonTypeName': 'Fachunterricht',
      'hasToBeSigned': open,
      'signedByOne': !open,
      'isSubstitute': substitute ? 1 : 0,
      'rooms': [
        {'name': 'R 5AT'},
      ],
      'teachers': [
        {'firstName': 'Alexander', 'lastName': 'Larcher'},
      ],
      'lessonContents': [
        for (final content in contents) {'name': content},
      ],
      'homeworkExams': const [],
      'grades': const [],
      'missingStudents': const [],
    });

List<ClassRegisterLesson> _lessons() => [
      _lesson('2026-06-12', 1, 'Projektmanagement',
          contents: ['Abschlussfeier']),
      _lesson('2026-06-12', 2, 'Mathematik', open: true, substitute: true),
      _lesson('2026-06-11', 3, 'Deutsch', contents: ['Erörterung']),
    ];

/// Opens the class register as Extras does, below the shell of the new
/// design, with [loader] in place of the server.
Future<Store<AppState, AppStateBuilder, AppActions>> _pump(
  WidgetTester tester, {
  Future<List<ClassRegisterLesson>> Function()? loader,
  Size size = _phone,
  ThemeMode themeMode = ThemeMode.light,
  bool amoled = false,
  bool newDesign = true,
  String languageCode = 'de',
  bool fromExtras = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(
    initialState: _state(languageCode: languageCode),
    newDesign: newDesign,
  );
  await pumpApp(
    tester,
    store: store,
    home: DaysContainer(),
    themeMode: themeMode,
    darkTheme: themeController.buildTheme(
      brightness: Brightness.dark,
      amoledMode: amoled,
    ),
  );
  await settleFor(tester);
  if (fromExtras) {
    scaffoldKey!.currentState!
        .selectContentWidget(const ExtrasPageContainer(), Pages.extras);
    await settleFor(tester, duration: const Duration(milliseconds: 500));
  }
  scaffoldKey!.currentState!.selectContentWidget(
    ClassRegisterPage(
        key: UniqueKey(), loader: loader ?? () async => _lessons()),
    Pages.classRegister,
  );
  await settleFor(tester, duration: const Duration(milliseconds: 500));
  return store;
}

Finder _key(String key) => find.byKey(Key(key));

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() async {
    await resetTestState();
  });

  group('design switch', () {
    testWidgets('the new design shows the new page', (tester) async {
      await _pump(tester);

      expect(find.byType(ClassRegisterPageNew), findsOneWidget);
      expect(_key('class-register-app-header'), findsOneWidget);
      expect(find.byType(GlassPageHeader), findsOneWidget);
      expect(find.byType(ResponsiveAppBar), findsNothing);
      expect(find.byType(NewDesignReadable), findsNothing);
      expect(find.byType(Card), findsNothing);
      // No icon in the title, the name of the page is enough.
      expect(
        find.descendant(
          of: find.byType(GlassPageHeader),
          matching: find.byIcon(Icons.fact_check_outlined),
        ),
        findsNothing,
      );
    });

    testWidgets('Legacy shows the old page', (tester) async {
      await _pump(tester, newDesign: false);

      expect(find.byType(ClassRegisterPage), findsOneWidget);
      expect(find.byType(ClassRegisterPageNew), findsNothing);
      expect(find.byType(ResponsiveAppBar), findsOneWidget);
      expect(find.text('Projektmanagement'), findsOneWidget);
    });

    testWidgets('switching applies at once, keeping the lessons',
        (tester) async {
      var loads = 0;
      final store = await _pump(tester, loader: () async {
        loads++;
        return _lessons();
      });

      await store.actions.settingsActions.legacyDesign(true);
      await settleFor(tester);
      expect(find.byType(ClassRegisterPageNew), findsNothing);
      expect(find.byType(ResponsiveAppBar), findsOneWidget);
      expect(find.text('Projektmanagement'), findsOneWidget);

      await store.actions.settingsActions.legacyDesign(false);
      await settleFor(tester);
      expect(find.byType(ClassRegisterPageNew), findsOneWidget);
      expect(find.text('Projektmanagement'), findsOneWidget);
      expect(loads, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('content', () {
    testWidgets('days as headings, lessons as rows in cards', (tester) async {
      await _pump(tester);

      final l10n = tester.element(find.byType(ClassRegisterPageNew)).l10n;
      expect(find.text(l10n.text('classRegister.title')), findsOneWidget);
      expect(find.byType(GlassSectionHeading), findsNWidgets(2));
      expect(find.textContaining('Freitag, 12. Juni 2026', findRichText: true),
          findsOneWidget);
      expect(
          find.textContaining('Donnerstag, 11. Juni 2026', findRichText: true),
          findsOneWidget);
      expect(_key('class-register-lesson'), findsNWidgets(3));
      expect(find.byType(GlassCard), findsNWidgets(2));
      expect(find.text('Projektmanagement'), findsOneWidget);
      expect(find.textContaining('5AT · R 5AT'), findsWidgets);
      expect(find.text('1 Inhalt'), findsNWidgets(2));
      expect(find.text('Abschlussfeier'), findsOneWidget);
      expect(find.text('Lehrpersonen: Alexander Larcher'), findsNWidgets(3));
      expect(find.text('Offen'), findsOneWidget);
      expect(find.text('Supplenz'), findsOneWidget);
      expect(
        tester.widget<Text>(_key('class-register-summary')).data,
        startsWith('3 Stunden'),
      );

      // The newest day comes first.
      expect(
        tester
            .getTopLeft(find.textContaining('Freitag, 12. Juni 2026',
                findRichText: true))
            .dy,
        lessThan(tester
            .getTopLeft(find.textContaining('Donnerstag, 11. Juni 2026',
                findRichText: true))
            .dy),
      );
    });

    testWidgets('headings are headings for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);

      expect(
        tester.getSemantics(_key('class-register-header-title')),
        isSemantics(label: 'Klassenbuch', isHeader: true),
      );
      expect(
        find.bySemanticsLabel(RegExp('Freitag, 12. Juni 2026')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('the refresh disc and pulling load again', (tester) async {
      var loads = 0;
      await _pump(tester, loader: () async {
        loads++;
        return _lessons();
      });
      expect(loads, 1);

      await tester.tap(_key('class-register-refresh'));
      await settleFor(tester);
      expect(loads, 2);

      await tester.fling(
        _key('class-register-list'),
        const Offset(0, 400),
        1000,
      );
      await settleFor(tester, duration: const Duration(seconds: 1));
      expect(loads, 3);
    });

    testWidgets('a lesson shows everything Legacy shows', (tester) async {
      final lesson = ClassRegisterLesson.fromJson({
        'date': '2026-06-12',
        'hour': 2,
        'toHour': 3,
        'timeStart': 30000,
        'timeEnd': 33000,
        'className': '5AT',
        'subject': {'name': 'Physik'},
        'lessonTypeName': 'Fachunterricht',
        'description': 'Versuch zum freien Fall',
        'note': 'Laborkittel mitbringen',
        'signedByCurrentUser': true,
        'signedByOne': true,
        'isSubstitute': 1,
        'rooms': [
          {'name': 'Labor 1'},
          {'name': 'R 2.14'},
        ],
        'teachers': [
          {'firstName': 'Maria', 'lastName': 'Huber'},
          {'firstName': 'Paul', 'lastName': 'Gruber'},
        ],
        'lessonContents': const [],
        'homeworkExams': [
          {'name': 'Protokoll'},
        ],
        'grades': [
          {'name': 'Mitarbeit', 'grade': '8'},
        ],
        'missingStudents': [
          {'firstName': 'Anna', 'lastName': 'Rossi'},
        ],
        'criticalObservations': ['Handy im Unterricht'],
      });
      for (final newDesign in [false, true]) {
        await _pump(
          tester,
          newDesign: newDesign,
          size: const Size(1280, 800),
          loader: () async => [lesson],
        );
        final reason = 'newDesign: $newDesign';
        for (final text in [
          'Physik',
          '2 - 3',
          '08:20 - 09:10',
          '5AT',
          'Labor 1, R 2.14',
          'Fachunterricht',
          'Versuch zum freien Fall',
          // Signed state, substitution and what was entered.
          'Unterschrieben',
          'Supplenz',
          '1 Aufgabe',
          '1 Bewertung',
          '1 Absenz',
          'Protokoll',
          'Mitarbeit: 8',
          'Anna Rossi',
          'Laborkittel mitbringen',
          'Handy im Unterricht',
          'Lehrpersonen: Maria Huber, Paul Gruber',
        ]) {
          expect(find.textContaining(text), findsWidgets,
              reason: '$text, $reason');
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 6));
      }
    });

    for (final (name, json, label) in const [
      ('open', {'hasToBeSigned': true}, 'Offen'),
      ('recorded', {'signedByOne': true}, 'Eingetragen'),
      ('read only', <String, Object>{}, 'Nur Lesen'),
    ]) {
      testWidgets('the state of a $name lesson', (tester) async {
        await _pump(
          tester,
          loader: () async => [
            ClassRegisterLesson.fromJson({
              'date': '2026-06-12',
              'hour': 1,
              'subject': {'name': 'Physik'},
              ...json,
            }),
          ],
        );
        expect(find.text(label), findsOneWidget);
      });
    }
  });

  group('states', () {
    testWidgets('loading shows the bar below the header', (tester) async {
      final completer = Completer<List<ClassRegisterLesson>>();
      await _pump(tester, loader: () => completer.future);

      expect(_key('class-register-loading'), findsOneWidget);
      expect(
        tester
            .widget<AnimatedLinearProgressIndicator>(
              find.byType(AnimatedLinearProgressIndicator),
            )
            .show,
        isTrue,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      completer.complete(_lessons());
      await settleFor(tester);
      expect(find.text('Projektmanagement'), findsOneWidget);
    });

    testWidgets('an error offers to try again', (tester) async {
      var fail = true;
      await _pump(tester, loader: () async {
        if (fail) throw const ClassRegisterLoadException();
        return _lessons();
      });

      expect(_key('class-register-error'), findsOneWidget);
      expect(find.text('Klassenbuch konnte nicht geladen werden.'),
          findsOneWidget);
      fail = false;
      await tester.tap(find.text('Erneut versuchen'));
      await settleFor(tester);
      expect(_key('class-register-error'), findsNothing);
      expect(find.text('Projektmanagement'), findsOneWidget);
    });

    testWidgets('no lessons', (tester) async {
      await _pump(tester, loader: () async => []);

      expect(_key('class-register-empty'), findsOneWidget);
      expect(find.text('Noch keine Klassenbucheinträge vorhanden'),
          findsOneWidget);
    });

    testWidgets('offline without lessons', (tester) async {
      wrapper.noInternet = true;
      await _pump(tester, loader: () async => throw Exception('offline'));

      expect(_key('class-register-offline'), findsOneWidget);
      expect(find.byType(GlassStateCard), findsOneWidget);
    });

    testWidgets('offline with saved lessons shows a hint', (tester) async {
      wrapper.noInternet = true;
      await _pump(tester);

      expect(_key('class-register-last-fetched'), findsOneWidget);
      expect(find.byType(GlassOfflineHint), findsOneWidget);
      expect(find.text('Projektmanagement'), findsOneWidget);
    });

    testWidgets('a saved register is shown, then refreshed', (tester) async {
      final payload = [
        {
          'date': '2026-06-12',
          'hour': 1,
          'subject': {'name': 'Gespeichert'},
        },
      ];
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final refresh = Completer<ClassRegisterPayloadSnapshot?>();
      final store = createStore(initialState: _state(), newDesign: true);
      await pumpApp(tester, store: store, home: DaysContainer());
      await settleFor(tester);
      scaffoldKey!.currentState!.selectContentWidget(
        ClassRegisterPage(
          key: UniqueKey(),
          cachedLoader: () async =>
              ClassRegisterPayloadSnapshot.fromPayload(payload),
          refreshLoader: () => refresh.future,
        ),
        Pages.classRegister,
      );
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(find.text('Gespeichert'), findsOneWidget);

      refresh.complete(ClassRegisterPayloadSnapshot.fromPayload([
        {
          ...payload.single,
          'subject': {'name': 'Neu'},
        },
      ]));
      await settleFor(tester);
      expect(find.text('Neu'), findsOneWidget);
    });
  });

  group('layouts', () {
    testWidgets('on a phone the list starts below the header', (tester) async {
      await _pump(tester, size: const Size(360, 640));

      expect(find.byType(FloatingNavigationBar), findsOneWidget);
      final header = tester.getRect(_key('class-register-app-header'));
      expect(header.left, 0);
      expect(header.top, 0);
      expect(
        tester.getRect(_key('class-register-summary')).top,
        greaterThanOrEqualTo(header.bottom),
      );
    });

    for (final size in const [Size(1280, 800), Size(800, 600)]) {
      testWidgets('at ${size.width} x ${size.height} the header floats',
          (tester) async {
        await _pump(tester, size: size);

        final header = tester.getRect(_key('class-register-app-header'));
        final card = tester.getRect(find.byType(GlassCard).first);
        expect(header.top, DesignTokens.gutter);
        expect(header.width, lessThanOrEqualTo(DesignTokens.contentMaxWidth));
        expect(card.left, header.left);
        expect(card.right, header.right);
        expect(tester.takeException(), isNull);
      });
    }

    for (final (name, themeMode, amoled) in const [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('AMOLED', ThemeMode.dark, true),
    ]) {
      testWidgets('320 px, text at 2.0, $name', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(
          tester,
          size: const Size(320, 640),
          themeMode: themeMode,
          amoled: amoled,
        );

        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(GlassCard).first).width,
          320 - 2 * DesignTokens.gutter,
        );
      });
    }
  });

  group('glass', () {
    testWidgets('only the header blurs, nothing in the list', (tester) async {
      await _pump(tester);

      expect(
        find.descendant(
          of: _key('class-register-list'),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(GlassPageHeader),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
    });

    testWidgets('high contrast has no blur and no light', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pump(tester, themeMode: ThemeMode.dark);

      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ClassRegisterPageNew),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.painter is GlassSheenPainter,
          ),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pump(tester);

      expect(find.text('Projektmanagement'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('navigation', () {
    testWidgets('back returns to Extras', (tester) async {
      await _pump(tester, fromExtras: true);

      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(find.byType(ClassRegisterPageNew), findsNothing);
      expect(find.byType(ExtrasPage), findsOneWidget);
    });
  });

  group('languages', () {
    for (final code in const ['de', 'it', 'en', 'lld']) {
      testWidgets('in $code', (tester) async {
        await _pump(tester, languageCode: code, size: const Size(320, 640));

        final l10n = tester.element(find.byType(ClassRegisterPageNew)).l10n;
        expect(
          tester.widget<Text>(_key('class-register-header-title')).data,
          l10n.text('classRegister.title'),
        );
        expect(
            find.text(l10n.text('classRegister.status.open')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
