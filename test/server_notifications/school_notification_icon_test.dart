import 'dart:math' as math;

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/dashboard_events.dart';
import 'package:dr/data.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/server_notifications/server_notification_visuals.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/test_harness.dart';

Future<void> _pumpIcon(
  WidgetTester tester,
  SchoolNotificationIcon icon, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: themeController.buildTheme(
      brightness: brightness,
      amoledMode: false,
    ),
    home: Scaffold(body: Center(child: icon)),
  ));
}

Finder _inIcon(Finder matching) => find.descendant(
    of: find.byType(SchoolNotificationIcon), matching: matching);

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}

/// The color of the tile behind the content of the icon.
Color _tileColor(WidgetTester tester) {
  final container = tester.widget<Container>(_inIcon(find.byType(Container)));
  return (container.decoration! as BoxDecoration).color!;
}

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  group('content by type (#153)', () {
    for (final type in ['absence', 'Absence', 'ABSENCE']) {
      testWidgets('$type shows a clock', (tester) async {
        await _pumpIcon(tester, SchoolNotificationIcon(type: type));
        expect(_inIcon(find.byIcon(Icons.schedule_rounded)), findsOneWidget);
        expect(_inIcon(find.byIcon(Icons.school_outlined)), findsNothing);
      });
    }

    for (final (hundredths, text) in [
      (1000, '10'),
      (800, '8'),
      (750, '7/8'),
      (775, '8-'),
      (825, '8+'),
      (760, '7,60'),
    ]) {
      testWidgets('a grade of $hundredths shows "$text"', (tester) async {
        await _pumpIcon(
          tester,
          SchoolNotificationIcon(type: 'grade', gradeHundredths: hundredths),
        );
        expect(_inIcon(find.text(text)), findsOneWidget);
        expect(_inIcon(find.byType(Icon)), findsNothing);
      });
    }

    testWidgets('the type of a grade is compared without case', (tester) async {
      await _pumpIcon(
        tester,
        const SchoolNotificationIcon(type: 'Grade', gradeHundredths: 900),
      );
      expect(_inIcon(find.text('9')), findsOneWidget);
    });

    testWidgets('a grade without a known value shows the grades icon',
        (tester) async {
      await _pumpIcon(tester, const SchoolNotificationIcon(type: 'grade'));
      expect(_inIcon(find.byIcon(Icons.auto_graph_rounded)), findsOneWidget);
      expect(_inIcon(find.byIcon(Icons.school_outlined)), findsNothing);
      expect(_inIcon(find.byType(Text)), findsNothing);
    });

    for (final type in [
      null,
      'message',
      'messageShared',
      'observation',
      'generic',
      '',
    ]) {
      testWidgets('"$type" keeps the school icon', (tester) async {
        // A value is only shown for grades.
        await _pumpIcon(
          tester,
          SchoolNotificationIcon(type: type, gradeHundredths: 800),
        );
        expect(_inIcon(find.byIcon(Icons.school_outlined)), findsOneWidget);
        expect(_inIcon(find.byType(Text)), findsNothing);
      });
    }

    testWidgets('stays decorative for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpIcon(
        tester,
        const SchoolNotificationIcon(type: 'grade', gradeHundredths: 800),
      );
      expect(find.bySemanticsLabel('8'), findsNothing);
      semantics.dispose();
    });
  });

  group('the grade fits its tile', () {
    for (final scale in [1.0, 2.0]) {
      for (final size in [40.0, 36.0]) {
        for (final hundredths in [1000, 750, 775, 760]) {
          testWidgets('$hundredths at text scale $scale in $size px',
              (tester) async {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
                tester.platformDispatcher.clearTextScaleFactorTestValue);
            await _pumpIcon(
              tester,
              SchoolNotificationIcon(
                type: 'grade',
                gradeHundredths: hundredths,
                size: size,
              ),
            );
            expect(tester.takeException(), isNull);
            final tile = tester.getRect(find.byType(SchoolNotificationIcon));
            final text = tester.getRect(_inIcon(find.byType(Text)));
            expect(tile.size, Size(size, size));
            expect(tile.contains(text.topLeft), isTrue);
            expect(tile.contains(text.bottomRight - const Offset(0.01, 0.01)),
                isTrue);
          });
        }
      }
    }
  });

  group('colors', () {
    for (final brightness in Brightness.values) {
      for (final hundredths in [400, 550, 575, 600, 1000]) {
        testWidgets(
            '$hundredths reaches WCAG AA, ${brightness.name}, '
            'like the grade badges', (tester) async {
          await _pumpIcon(
            tester,
            SchoolNotificationIcon(type: 'grade', gradeHundredths: hundredths),
            brightness: brightness,
          );
          final scheme =
              Theme.of(tester.element(find.byType(SchoolNotificationIcon)))
                  .colorScheme;
          final text = tester.widget<Text>(_inIcon(find.byType(Text)));
          final background = _tileColor(tester);
          expect(
            background,
            hundredths < 550
                ? scheme.errorContainer
                : hundredths <= 575
                    ? scheme.warningContainer
                    : scheme.successContainer,
          );
          expect(_contrast(text.style!.color!, background),
              greaterThanOrEqualTo(4.5));
        });
      }

      testWidgets('neutral with grade colors off, ${brightness.name}',
          (tester) async {
        await _pumpIcon(
          tester,
          const SchoolNotificationIcon(
            type: 'grade',
            gradeHundredths: 400,
            colorGrades: false,
          ),
          brightness: brightness,
        );
        final scheme =
            Theme.of(tester.element(find.byType(SchoolNotificationIcon)))
                .colorScheme;
        final text = tester.widget<Text>(_inIcon(find.byType(Text)));
        expect(_tileColor(tester), scheme.secondaryContainer);
        expect(text.style!.color, scheme.onSecondaryContainer);
        expect(_contrast(text.style!.color!, _tileColor(tester)),
            greaterThanOrEqualTo(4.5));
      });

      testWidgets('the clock keeps the tile of the school, ${brightness.name}',
          (tester) async {
        await _pumpIcon(
          tester,
          const SchoolNotificationIcon(type: 'absence'),
          brightness: brightness,
        );
        final scheme =
            Theme.of(tester.element(find.byType(SchoolNotificationIcon)))
                .colorScheme;
        expect(_tileColor(tester), scheme.secondaryContainer);
      });
    }
  });

  group('notificationGradeHundredths', () {
    final gradesState =
        AppState((b) => b.gradesState.subjects = ListBuilder<Subject>([
              buildSubject(name: 'Mathematik', grades: {
                Semester.first: BuiltList<GradeDetail>([
                  buildGradeDetail(id: 42, date: fixtureNow, grade: 850),
                ]),
              }),
            ])).gradesState;
    final days = [
      buildDay(date: fixtureNow, homework: [
        buildHomework(id: 43, type: HomeworkType.grade, grade: '7.50'),
        buildHomework(id: 44, type: HomeworkType.grade, grade: 'abc'),
        buildHomework(id: 45, type: HomeworkType.grade),
        buildHomework(id: 42, type: HomeworkType.grade, grade: '4'),
        buildHomework(id: 46, grade: '9'),
      ]),
    ];
    int? lookUp(String? type, int? objectId) => notificationGradeHundredths(
          buildNotification(type: type, objectId: objectId),
          grades: gradesState,
          days: days,
        );

    test('finds the grade in the grades, then on the dashboard', () {
      expect(lookUp('grade', 42), 850);
      expect(lookUp('GRADE', 42), 850);
      expect(lookUp('grade', 43), 750);
    });

    test('is null when the value is not known', () {
      expect(lookUp('grade', null), isNull);
      expect(lookUp('grade', 99), isNull);
      expect(lookUp('grade', 44), isNull);
      expect(lookUp('grade', 45), isNull);
      // Homework is no grade, even with a grade field.
      expect(lookUp('grade', 46), isNull);
      expect(
        notificationGradeHundredths(
          buildNotification(type: 'grade', objectId: 43),
          grades: gradesState,
          days: null,
        ),
        isNull,
      );
    });

    test('is null for every other type', () {
      for (final type in [null, 'absence', 'message', 'observation']) {
        expect(lookUp(type, 42), isNull, reason: '$type');
      }
    });

    test('agrees with the events on the dashboard', () {
      final state = AppState((b) => b
        ..gradesState.replace(gradesState)
        ..dashboardState.allDays = ListBuilder<Day>(days)
        ..notificationState.notifications = ListBuilder<Notification>([
          buildNotification(type: 'grade', objectId: 42),
          buildNotification(id: 2, type: 'grade', objectId: 43),
        ]));
      final events = dashboardEvents(state);
      for (final event in events) {
        expect(
          notificationGradeHundredths(event.notification!,
              grades: state.gradesState, days: state.dashboardState.allDays),
          event.gradeHundredths,
        );
      }
      expect(events.map((event) => event.gradeHundredths),
          unorderedEquals([850, 750]));
    });
  });
}
