import 'dart:math' as math;

import 'package:dr/school_notification_grade.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/ui/server_notifications/server_notification_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// The grade of a feed text with [value] as its grade.
SchoolNotificationGrade? _grade(String value) =>
    parseSchoolNotificationGrade('Neue Bewertung "Fach" "Test" "$value"');

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

    // As the grades page writes them.
    for (final (value, text) in [
      ('10', '10'),
      ('8', '8'),
      ('7½', '7/8'),
      ('7/8', '7/8'),
      ('8-', '8-'),
      ('8+', '8+'),
      ('4', '4'),
    ]) {
      testWidgets('a grade of $value shows "$text"', (tester) async {
        await _pumpIcon(
          tester,
          SchoolNotificationIcon(type: 'grade', grade: _grade(value)),
        );
        expect(_inIcon(find.text(text)), findsOneWidget);
        expect(_inIcon(find.byType(Icon)), findsNothing);
      });
    }

    testWidgets('the type of a grade is compared without case', (tester) async {
      await _pumpIcon(
        tester,
        SchoolNotificationIcon(type: 'Grade', grade: _grade('9')),
      );
      expect(_inIcon(find.text('9')), findsOneWidget);
    });

    testWidgets('a short grade the app cannot read is shown as written',
        (tester) async {
      await _pumpIcon(
        tester,
        SchoolNotificationIcon(type: 'grade', grade: _grade('gut')),
      );
      expect(_inIcon(find.text('gut')), findsOneWidget);
      final scheme =
          Theme.of(tester.element(find.byType(SchoolNotificationIcon)))
              .colorScheme;
      expect(_tileColor(tester), scheme.secondaryContainer);
    });

    testWidgets('a grade without a usable text shows the grades icon',
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
          SchoolNotificationIcon(type: type, grade: _grade('8')),
        );
        expect(_inIcon(find.byIcon(Icons.school_outlined)), findsOneWidget);
        expect(_inIcon(find.byType(Text)), findsNothing);
      });
    }

    testWidgets('stays decorative for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpIcon(
        tester,
        SchoolNotificationIcon(type: 'grade', grade: _grade('8')),
      );
      expect(find.bySemanticsLabel('8'), findsNothing);
      semantics.dispose();
    });
  });

  group('the grade fits its tile', () {
    for (final scale in [1.0, 2.0]) {
      for (final size in [40.0, 36.0]) {
        for (final value in ['10', '7½', '8-', '7,6', 'gut']) {
          testWidgets('$value at text scale $scale in $size px',
              (tester) async {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
                tester.platformDispatcher.clearTextScaleFactorTestValue);
            await _pumpIcon(
              tester,
              SchoolNotificationIcon(
                type: 'grade',
                grade: _grade(value),
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

  group('colors like the grade badges of the grades page', () {
    for (final brightness in Brightness.values) {
      for (final (value, hundredths) in [
        ('4', 400),
        ('5+', 525),
        ('5½', 550),
        ('6-', 575),
        ('6', 600),
        ('10', 1000),
      ]) {
        testWidgets('$value, ${brightness.name}', (tester) async {
          await _pumpIcon(
            tester,
            SchoolNotificationIcon(type: 'grade', grade: _grade(value)),
            brightness: brightness,
          );
          final scheme =
              Theme.of(tester.element(find.byType(SchoolNotificationIcon)))
                  .colorScheme;
          final text = tester.widget<Text>(_inIcon(find.byType(Text)));
          final background = _tileColor(tester);
          // The same function decides as for the badges of the grades page.
          final (foreground, badge) = gradeBadgeColors(scheme, hundredths)!;
          expect((text.style!.color, background), (foreground, badge));
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
          SchoolNotificationIcon(
            type: 'grade',
            grade: _grade('4'),
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
}
