import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/extras_page_container.dart';
import 'package:dr/course_materials.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/page_payload_cache.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/course_materials_page.dart';
import 'package:dr/ui/course_materials_page_new.dart';
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

Map<String, Object?> _coursePayload(
        int id, String title, List<String> topics) =>
    {
      'id': id,
      'course': {'id': id, 'title': title},
      'topics': [
        for (final (index, topic) in topics.indexed)
          {
            'id': id * 10 + index,
            'courseContentId': id,
            'title': topic,
            'entries': [
              {
                'id': id * 100 + index,
                'courseContentId': id,
                'type': 'file',
                'file': 'f.pdf',
                'title': '$topic file',
                'originalName': '$topic.pdf',
              },
            ],
          },
      ],
    };

List<CourseMaterialCourse> _courses() => [
      CourseMaterialCourse.fromJson(
        _coursePayload(10, 'Math course', ['Equations', 'Functions']),
        CourseMaterialSource.fromJson(
          {'classId': 1, 'subjectId': 2, 'subjectName': 'Mathematik'},
        ),
      ),
      CourseMaterialCourse.fromJson(
        _coursePayload(11, 'Art course', ['Colours']),
        CourseMaterialSource.fromJson(
          {'classId': 1, 'subjectId': 3, 'subjectName': 'Kunst'},
        ),
      ),
    ];

PagePayloadSnapshot<List<Map<String, dynamic>>> _snapshot() =>
    PagePayloadSnapshot<List<Map<String, dynamic>>>.fromPayload(
      courseMaterialCoursesToPayload(_courses()),
    );

/// Opens the course materials as Extras does, below the shell of the new
/// design. [page] replaces the page, to give it other loaders.
Future<Store<AppState, AppStateBuilder, AppActions>> _pump(
  WidgetTester tester, {
  Widget? page,
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
    page ??
        CourseMaterialsPage(key: UniqueKey(), loader: () async => _courses()),
    Pages.courseMaterials,
  );
  await settleFor(tester, duration: const Duration(milliseconds: 500));
  return store;
}

Finder _key(String key) => find.byKey(Key(key));

Finder _heading(String text) => find.textContaining(text, findRichText: true);

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

      expect(find.byType(CourseMaterialsPageNew), findsOneWidget);
      expect(_key('course-materials-app-header'), findsOneWidget);
      expect(find.byType(ResponsiveAppBar), findsNothing);
      expect(find.byType(NewDesignReadable), findsNothing);
      expect(find.byType(Card), findsNothing);
      expect(
        find.descendant(
          of: find.byType(GlassPageHeader),
          matching: find.byIcon(Icons.folder_copy_outlined),
        ),
        findsNothing,
      );
    });

    testWidgets('Legacy shows the old page', (tester) async {
      await _pump(tester, newDesign: false);

      expect(find.byType(CourseMaterialsPageNew), findsNothing);
      expect(find.byType(ResponsiveAppBar), findsOneWidget);
      expect(find.text('Equations'), findsOneWidget);
    });

    testWidgets('switching applies at once', (tester) async {
      final store = await _pump(tester);

      await store.actions.settingsActions.legacyDesign(true);
      await settleFor(tester);
      expect(find.byType(CourseMaterialsPageNew), findsNothing);
      expect(find.byType(ResponsiveAppBar), findsOneWidget);

      await store.actions.settingsActions.legacyDesign(false);
      await settleFor(tester);
      expect(find.byType(CourseMaterialsPageNew), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('content', () {
    testWidgets('courses as headings, topics as closed rows', (tester) async {
      await _pump(tester);

      expect(find.byType(GlassSectionHeading), findsNWidgets(2));
      expect(_heading('Mathematik'), findsOneWidget);
      expect(_heading('Kunst'), findsOneWidget);
      expect(find.byType(GlassCard), findsNWidgets(2));
      expect(find.text('Equations'), findsOneWidget);
      expect(find.text('Functions'), findsOneWidget);
      // Closed topics build none of their materials.
      expect(find.text('Equations file'), findsNothing);
      expect(
        tester.widget<Text>(_key('course-materials-summary')).data,
        startsWith('3 Materialien'),
      );
      // Each topic is on a layer of its own.
      expect(
        find.ancestor(
          of: find.text('Equations'),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
      expect(
        tester.widget<RepaintBoundary>(
          find.byKey(const ValueKey('course-materials-topic-100')),
        ),
        isNotNull,
      );
    });

    testWidgets('a topic opens in place and closes again', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Equations'));
      await settleFor(tester);
      expect(find.text('Equations file'), findsOneWidget);
      expect(find.text('Functions file'), findsNothing);

      await tester.tap(find.text('Equations'));
      await settleFor(tester);
      expect(find.text('Equations file'), findsNothing);
    });

    testWidgets('topics and materials are buttons for screen readers',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);

      expect(
        find.bySemanticsLabel('Equations, 1'),
        findsOneWidget,
      );
      await tester.tap(find.text('Equations'));
      await settleFor(tester);
      expect(
        tester.getSemantics(
          find.descendant(
            of: find.byKey(const ValueKey('course-materials-entry-1000')),
            matching: find.byType(InkWell),
          ),
        ),
        isSemantics(
          label: 'Equations file',
          isButton: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('a material opens, and an outdated one tells so',
        (tester) async {
      final opened = <int>[];
      final opening = Completer<CourseMaterialOpenResult>();
      await _pump(
        tester,
        page: CourseMaterialsPage(
          key: UniqueKey(),
          loader: () async => _courses(),
          entryOpener: (entry) {
            opened.add(entry.id);
            return opening.future;
          },
        ),
      );
      await tester.tap(find.text('Equations'));
      await settleFor(tester);
      await tester.tap(find.text('Equations file'));
      await tester.pump();
      expect(opened, [1000]);
      expect(_key('course-materials-opening'), findsOneWidget);

      opening.complete(CourseMaterialOpenResult.openedOutdated);
      await settleFor(tester);
      expect(_key('course-materials-opening'), findsNothing);
      expect(
        find.text('Die aktuelle Version konnte nicht geladen werden. '
            'Geöffnet wurde die zuletzt gespeicherte Version.'),
        findsOneWidget,
      );
    });

    testWidgets('the refresh disc loads again', (tester) async {
      var loads = 0;
      await _pump(
        tester,
        page: CourseMaterialsPage(
          key: UniqueKey(),
          loader: () async {
            loads++;
            return _courses();
          },
        ),
      );
      await tester.tap(_key('course-materials-refresh'));
      await settleFor(tester);
      expect(loads, 2);
    });

    testWidgets('a material shows its kind and when it was changed, as Legacy',
        (tester) async {
      final payload = _coursePayload(12, 'Physics course', ['Optics']);
      final entry = ((payload['topics']! as List).single
          as Map<String, Object?>)['entries']! as List;
      (entry.single as Map<String, Object?>)
        ..['typeName'] = 'Arbeitsblatt'
        // The server's key is in lower case.
        ..['lastmodified'] = '2026-11-03 10:15';
      final courses = [
        CourseMaterialCourse.fromJson(
          payload,
          CourseMaterialSource.fromJson(
            {'classId': 1, 'subjectId': 4, 'subjectName': 'Physik'},
          ),
        ),
      ];
      expect(courses.single.topics.single.entries.single.lastModified,
          '2026-11-03 10:15');

      for (final newDesign in [false, true]) {
        await _pump(
          tester,
          newDesign: newDesign,
          size: const Size(1280, 800),
          page: CourseMaterialsPage(
            key: UniqueKey(),
            loader: () async => courses,
          ),
        );
        await tester.tap(find.text('Optics'));
        await settleFor(tester);
        // Legacy shows both as texts of their own, the new design on one
        // line: the same words either way.
        expect(find.textContaining('Arbeitsblatt'), findsOneWidget,
            reason: 'newDesign: $newDesign');
        expect(find.textContaining('2026-11-03 10:15'), findsOneWidget,
            reason: 'newDesign: $newDesign');
        if (newDesign) {
          expect(
            find.text('Arbeitsblatt · 2026-11-03 10:15'),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 6));
      }
    });
  });

  group('states', () {
    testWidgets('loading shows the bar below the header', (tester) async {
      final completer = Completer<List<CourseMaterialCourse>>();
      await _pump(
        tester,
        page: CourseMaterialsPage(
          key: UniqueKey(),
          loader: () => completer.future,
        ),
      );

      expect(_key('course-materials-loading'), findsOneWidget);
      expect(
        tester
            .widget<AnimatedLinearProgressIndicator>(
              find.byType(AnimatedLinearProgressIndicator),
            )
            .show,
        isTrue,
      );
      completer.complete(_courses());
      await settleFor(tester);
      expect(find.text('Equations'), findsOneWidget);
    });

    testWidgets('an incomplete first load is an error card', (tester) async {
      await _pump(
        tester,
        languageCode: 'en',
        page: CourseMaterialsPage(
          key: UniqueKey(),
          cachedLoader: () async => null,
          refreshLoader: () async =>
              throw const CourseMaterialsIncompleteException(),
        ),
      );

      expect(_key('course-materials-error'), findsOneWidget);
      expect(
          find.text('Course materials could not be loaded.'), findsOneWidget);
      expect(find.text('Not all courses could be loaded.'), findsOneWidget);
    });

    for (final (name, error, text) in const [
      (
        'incomplete',
        CourseMaterialsIncompleteException(),
        'Not all courses could be loaded. '
            'Showing the last completely loaded version.',
      ),
      (
        'failed',
        CourseMaterialsLoadException(),
        'Course materials could not be updated. '
            'Showing the last saved version.',
      ),
    ]) {
      testWidgets('a $name refresh is a hint above the saved courses',
          (tester) async {
        await _pump(
          tester,
          languageCode: 'en',
          page: CourseMaterialsPage(
            key: UniqueKey(),
            cachedLoader: () async => _snapshot(),
            refreshLoader: () async => throw error,
          ),
        );

        expect(_key('course-materials-refresh-failed'), findsOneWidget);
        expect(find.byType(GlassOfflineHint), findsOneWidget);
        expect(find.text(text), findsOneWidget);
        expect(find.byIcon(Icons.sync_problem_rounded), findsOneWidget);
        expect(find.text('Equations'), findsOneWidget);
      });
    }

    testWidgets('no materials', (tester) async {
      await _pump(
        tester,
        page: CourseMaterialsPage(key: UniqueKey(), loader: () async => []),
      );

      expect(_key('course-materials-empty'), findsOneWidget);
      expect(
          find.text('Keine Unterrichtsmaterialien vorhanden'), findsOneWidget);
    });

    testWidgets('offline without materials', (tester) async {
      wrapper.noInternet = true;
      await _pump(
        tester,
        page: CourseMaterialsPage(
          key: UniqueKey(),
          loader: () async => throw Exception('offline'),
        ),
      );

      expect(_key('course-materials-offline'), findsOneWidget);
    });
  });

  group('layouts', () {
    for (final size in const [Size(1280, 800), Size(800, 600)]) {
      testWidgets('at ${size.width} x ${size.height} the header floats',
          (tester) async {
        await _pump(tester, size: size);

        final header = tester.getRect(_key('course-materials-app-header'));
        final card = tester.getRect(find.byType(GlassCard).first);
        expect(header.top, DesignTokens.gutter);
        expect(header.width, lessThanOrEqualTo(DesignTokens.contentMaxWidth));
        expect(card.left, header.left);
        expect(card.right, header.right);
      });
    }

    for (final (name, themeMode, amoled) in const [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('AMOLED', ThemeMode.dark, true),
    ]) {
      testWidgets('320 px, text at 2.0, $name, a topic open', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(
          tester,
          size: const Size(320, 640),
          themeMode: themeMode,
          amoled: amoled,
        );
        await tester.tap(find.text('Equations'));
        await settleFor(tester);

        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(GlassCard).first).width,
          320 - 2 * DesignTokens.gutter,
        );
        expect(
          tester
              .getSize(
                  find.byKey(const ValueKey('course-materials-entry-1000')))
              .height,
          greaterThanOrEqualTo(48),
        );
      });
    }
  });

  group('glass', () {
    testWidgets('only the header blurs, nothing in the list', (tester) async {
      await _pump(tester);

      expect(
        find.descendant(
          of: _key('course-materials-list'),
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
          of: find.byType(CourseMaterialsPageNew),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.painter is GlassSheenPainter,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('reduced motion opens a topic at once', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pump(tester);

      await tester.tap(find.text('Equations'));
      await tester.pump();
      expect(find.text('Equations file'), findsOneWidget);
      expect(
        tester
            .widget<SizeTransition>(find.ancestor(
              of: find.text('Equations file'),
              matching: find.byType(SizeTransition),
            ))
            .sizeFactor
            .value,
        1,
      );
    });
  });

  group('navigation', () {
    testWidgets('back returns to Extras', (tester) async {
      await _pump(tester, fromExtras: true);

      await tester.tap(find.byType(BackButton));
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(find.byType(CourseMaterialsPageNew), findsNothing);
      expect(find.byType(ExtrasPage), findsOneWidget);
    });
  });

  group('languages', () {
    for (final code in const ['de', 'it', 'en', 'lld']) {
      testWidgets('in $code', (tester) async {
        await _pump(tester, languageCode: code, size: const Size(320, 640));

        final l10n = tester.element(find.byType(CourseMaterialsPageNew)).l10n;
        expect(
          tester.widget<Text>(_key('course-materials-header-title')).data,
          l10n.text('courseMaterials.title'),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
