import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/absences_page_container.dart';
import 'package:dr/container/certificate_container.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/exam_calendar_container.dart';
import 'package:dr/container/extras_page_container.dart';
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/data.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/course_materials_page.dart';
import 'package:dr/ui/dashboard_app_header.dart';
import 'package:dr/ui/notepad_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

// #140: the top bar looks the same on every page of the new design, at
// every window size: same place, height and width, the same distance of
// the first and the last element from its edges, and nothing below it.

/// The window sizes, and the text scale of the system.
const _sizes = <String, (Size, double)>{
  'phone portrait': (Size(412, 900), 1),
  'phone portrait, text at 200 %': (Size(412, 900), 2),
  'phone landscape': (Size(900, 412), 1),
  'tablet': (Size(820, 1180), 1),
  'desktop': (Size(1280, 800), 1),
  'desktop, text at 200 %': (Size(1280, 800), 2),
  'wide desktop': (Size(1920, 1080), 1),
};

AppState _state() => AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
    });

/// The pages, one of each kind of header: the dashboard with its own
/// header, destinations without a back button with one and two columns,
/// and a page with a back button.
final _pages = <String, (Widget, Pages)?>{
  'dashboard': null,
  'extras': (const ExtrasPageContainer(), Pages.extras),
  'absences (two columns)': (const AbsencesPageContainer(), Pages.absences),
  'course materials (back)': (
    CourseMaterialsPage(loader: () async => const []),
    Pages.courseMaterials,
  ),
};

/// Where the parts of the visible header are.
class _Header {
  _Header(this.surface, this.first, this.lastEnd, this.back, this.bodyTop);

  final Rect surface;

  /// Left edge of the first element (back button, logo or title).
  final double first;

  /// Right edge of the last button, if there is one.
  final double? lastEnd;
  final Rect? back;

  /// Top of the highest text of the page below the header.
  final double? bodyTop;

  double get startInset => first - surface.left;
  double? get endInset => lastEnd == null ? null : surface.right - lastEnd!;
}

Future<_Header> _measure(
    WidgetTester tester, (Size, double) window, (Widget, Pages)? page) async {
  final (size, textScale) = window;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(initialState: _state(), newDesign: true);
  await pumpApp(tester, store: store, home: DaysContainer());
  await settleFor(tester);
  if (page != null) {
    scaffoldKey!.currentState!.selectContentWidget(page.$1, page.$2);
    await settleFor(tester, duration: const Duration(milliseconds: 500));
  }
  final shell = find.byType(GlassHeaderShell).hitTestable().last;
  final key = tester.widget<GlassHeaderShell>(shell).surfaceKey;
  final surface = tester.getRect(find.byKey(key).hitTestable().last);
  Iterable<Rect> rects(Finder finder) =>
      finder.hitTestable().evaluate().map((element) {
        final box = element.renderObject! as RenderBox;
        return box.localToGlobal(Offset.zero) & box.size;
      }).where((rect) => rect.width > 0);
  final back =
      rects(find.descendant(of: shell, matching: find.byType(BackButton)));
  bool inBack(Rect rect) => back.any((b) =>
      b.inflate(0.5).contains(rect.topLeft) &&
      b.inflate(0.5).contains(rect.bottomRight));
  // The back button, the logo of the dashboard and the texts.
  final parts = [
    ...back,
    ...rects(find.descendant(of: shell, matching: find.byType(NotepadMark))),
    ...rects(find.descendant(of: shell, matching: find.byType(Text)))
        .where((rect) => !inBack(rect)),
  ];
  // The buttons at the end, without the back button.
  final buttons = rects(find.descendant(
          of: shell,
          matching: find.byWidgetPredicate(
              (w) => w is IconButton || w is ButtonStyleButton)))
      .where((rect) => !inBack(rect))
      .toList();
  final below = rects(find.byType(Text))
      .where((rect) =>
          rect.top >= surface.top &&
          rect.left >= surface.left &&
          rect.right <= surface.right &&
          !rects(find.descendant(of: shell, matching: find.byType(Text)))
              .contains(rect))
      .map((rect) => rect.top);
  return _Header(
    surface,
    parts.map((rect) => rect.left).reduce((a, b) => a < b ? a : b),
    buttons.isEmpty
        ? null
        : buttons.map((rect) => rect.right).reduce((a, b) => a > b ? a : b),
    back.isEmpty ? null : back.first,
    below.isEmpty ? null : below.reduce((a, b) => a < b ? a : b),
  );
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() async {
    await resetTestState();
  });

  final measured = <String, Map<String, _Header>>{};
  for (final size in _sizes.entries) {
    for (final page in _pages.entries) {
      testWidgets('${page.key} at ${size.key}', (tester) async {
        (measured[size.key] ??= {})[page.key] =
            await _measure(tester, size.value, page.value);
        expect(tester.takeException(), isNull);
      });
    }

    test('at ${size.key} every header is the same', () {
      final headers = measured[size.key]!;
      expect(headers.keys, _pages.keys);
      final reference = headers['dashboard']!;
      final report = [
        for (final entry in headers.entries)
          '${entry.key}: ${entry.value.surface}, start '
              '${entry.value.startInset}, end ${entry.value.endInset}',
      ].join('\n');
      for (final entry in headers.entries) {
        final header = entry.value;
        final why = '${entry.key} differs from the dashboard\n$report';
        // Same place and size: no jump between pages.
        expect(header.surface, reference.surface, reason: why);
        if (header.back == null) {
          // The first element (logo or title) is as far from the edge.
          expect(header.startInset, reference.startInset, reason: why);
        } else {
          // A back button sits where the buttons at the end sit.
          expect(header.startInset, reference.endInset, reason: why);
        }
        // The last button is as far from the edge.
        if (header.endInset != null) {
          expect(header.endInset, reference.endInset, reason: why);
        }
        // Nothing of the page lies under the header.
        if (header.bodyTop != null) {
          expect(
              header.bodyTop, greaterThanOrEqualTo(header.surface.bottom - 0.5),
              reason: '${entry.key}: content below the header');
        }
      }
    });
  }

  // The legacy design keeps its own look: the app bar of Material with the
  // theme of the app (ResponsiveAppBar). Within it, the pages of the sidebar
  // must have the same bar: same height and place, the same leading button
  // (the menu on a phone, nothing beside the sidebar) and the title in the
  // same place.
  group('Legacy', () {
    final legacyPages = <String, (Widget, Pages)?>{
      'grades': (const GradesPageContainer(), Pages.grades),
      'absences': (const AbsencesPageContainer(), Pages.absences),
      'exam calendar': (const ExamCalendarContainer(), Pages.examCalendar),
      'certificate': (CertificateContainer(), Pages.certificate),
    };
    final legacy = <String, Map<String, (Rect, double, bool)>>{};
    for (final size in _sizes.entries) {
      for (final page in legacyPages.entries) {
        testWidgets('${page.key} at ${size.key}', (tester) async {
          tester.view.physicalSize = size.value.$1;
          tester.platformDispatcher.textScaleFactorTestValue = size.value.$2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final store = createStore(initialState: _state());
          await pumpApp(tester, store: store, home: DaysContainer());
          await settleFor(tester);
          scaffoldKey!.currentState!
              .selectContentWidget(page.value!.$1, page.value!.$2);
          await settleFor(tester, duration: const Duration(milliseconds: 500));
          final bar = find.byType(AppBar).hitTestable().last;
          final rect = tester.getRect(bar);
          final title = tester.getRect(find
              .descendant(of: bar, matching: find.byType(Text))
              .hitTestable()
              .first);
          final leading = find
              .descendant(
                  of: bar,
                  matching: find.byWidgetPredicate(
                      (w) => w is BackButton || w is DrawerButton))
              .evaluate()
              .isNotEmpty;
          (legacy[size.key] ??= {})[page.key] =
              (rect, title.left - rect.left, leading);
          expect(tester.takeException(), isNull);
        });
      }

      test('at ${size.key} the pages of the sidebar have the same bar', () {
        final bars = legacy[size.key]!;
        expect(bars.keys, legacyPages.keys);
        final reference = bars['grades']!;
        for (final entry in bars.entries) {
          expect(entry.value, reference,
              reason: '${entry.key} differs from grades: $bars');
        }
      });
    }
  });
}
