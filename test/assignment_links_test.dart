import 'dart:async';

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/calendar_actions.dart';
import 'package:dr/actions/dashboard_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/external_links.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/serializers.dart';
import 'package:dr/ui/days.dart';
import 'package:dr/ui/linkified_text.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _item(List<Object?> submissions) => <String, Object?>{
      'id': 1,
      'type': 'gradeGroup',
      'title': 'Test',
      'subtitle': 'Kapitel 3',
      'label': 'Mathematik',
      'warning': false,
      'checkable': false,
      'checked': false,
      'deleteable': false,
      'gradeGroupSubmissions': submissions,
    };

GradeGroupSubmission _link(String link, {String name = 'Arbeitsblatt'}) =>
    GradeGroupSubmission((b) => b
      ..type = 'link'
      ..link = link
      ..originalName = name
      ..timestamp = UtcDateTime(2026, 3, 27)
      ..typeName = 'Link'
      ..id = 7
      ..gradeGroupId = 3
      ..userId = 9);

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  group('parsing', () {
    late Store<AppState, AppStateBuilder, AppActions> store;

    setUp(() {
      store = Store<AppState, AppStateBuilder, AppActions>(
        appReducerBuilder.build(),
        AppState(),
        AppActions(),
      );
    });

    List<GradeGroupSubmission> load(List<Object?> submissions) {
      store.actions.dashboardActions.loaded(
        DaysLoadedPayload(
          (b) => b
            ..future = false
            ..markNewOrChangedEntries = false
            ..deduplicateEntries = false
            ..data = <Object>[
              <String, Object?>{
                'date': '2026-03-28',
                'items': <Object>[_item(submissions)],
              },
            ],
        ),
      );
      return store.state.dashboardState.allDays!.single.homework.single
          .gradeGroupSubmissions!
          .toList();
    }

    test('a link attached to an assignment survives parsing', () {
      final parsed = load(<Object?>[
        <String, Object?>{
          'id': 7,
          'type': 'link',
          'file': null,
          'link': ' https://example.org/worksheet ',
          'originalName': 'Arbeitsblatt',
          'timestamp': '2026-03-27 10:00:00',
          'typeName': 'Link',
          'gradeGroupId': 3,
          'userId': 9,
        },
      ]);
      expect(parsed, hasLength(1));
      expect(parsed.single.isLink, isTrue);
      expect(parsed.single.link, 'https://example.org/worksheet');
      expect(parsed.single.originalName, 'Arbeitsblatt');
    });

    test('a link needs nothing but its address', () {
      final parsed = load(<Object?>[
        <String, Object?>{'link': 'https://example.org/a'},
      ]);
      expect(parsed.single.isLink, isTrue);
      expect(parsed.single.originalName, 'https://example.org/a');
    });

    test('files and links can be attached side by side', () {
      final parsed = load(<Object?>[
        <String, Object?>{
          'id': 1,
          'type': 'file',
          'file': 'server.pdf',
          'originalName': 'Blatt.pdf',
          'timestamp': '2026-03-27 10:00:00',
          'typeName': 'Datei',
          'gradeGroupId': 3,
          'userId': 9,
        },
        <String, Object?>{'id': 2, 'type': 'link', 'link': 'example.org/a'},
        <String, Object?>{'id': 3, 'type': 'link', 'link': 'https://b.org'},
      ]);
      expect(parsed.map((s) => s.isLink), [false, true, true]);
    });

    test('an attachment with neither a file nor a link is left out', () {
      expect(
        load(<Object?>[
          <String, Object?>{'id': 1, 'type': 'link', 'link': '  '},
          <String, Object?>{'id': 2, 'type': 'file', 'originalName': 'a'},
        ]),
        isEmpty,
      );
    });

    test('a saved attachment from an older version is still a file', () {
      final saved = serializers.serializeWith(
        GradeGroupSubmission.serializer,
        GradeGroupSubmission((b) => b
          ..file = 'server.pdf'
          ..originalName = 'Blatt.pdf'
          ..timestamp = UtcDateTime(2026, 3, 27)
          ..typeName = 'Datei'
          ..id = 1
          ..gradeGroupId = 3
          ..userId = 9),
      )! as List<Object?>;
      final typeIndex = saved.indexOf('type');
      final old = [...saved]..removeRange(typeIndex, typeIndex + 2);

      final restored =
          serializers.deserializeWith(GradeGroupSubmission.serializer, old)!;

      expect(restored.isLink, isFalse);
      expect(restored.file, 'server.pdf');
    });

    test('a link on a lesson survives parsing', () {
      store.actions.calendarActions.loaded(
        CalendarLoadedPayload(
          config: SubstituteDetectionConfig((b) => b..enabled = false),
          data: <String, dynamic>{
            '2026-03-27': <String, Object?>{
              '1': <String, Object?>{
                '1': <String, Object?>{
                  '1': <String, Object?>{
                    'isLesson': 1,
                    'hour': 1,
                    'lesson': <String, Object?>{
                      'date': '2026-03-27',
                      'hour': 1,
                      'toHour': 1,
                      'classId': 1,
                      'className': '1A',
                      'timeStartObject': {'h': 8, 'm': 0, 'ts': 0},
                      'timeEndObject': {'h': 9, 'm': 0, 'ts': 0},
                      'subject': {'id': 1, 'name': 'Mathematik'},
                      'rooms': <Object>[],
                      'teachers': <Object>[],
                      'homeworkExams': <Object>[],
                      'lessonContents': <Object>[
                        <String, Object?>{
                          'name': 'Bruchrechnen',
                          'typeName': 'Lerninhalt',
                          'lessonContentSubmissions': <Object>[
                            <String, Object?>{
                              'id': '4',
                              'lessonContentId': '5',
                              'type': 'link',
                              'link': 'https://example.org/video',
                              'originalName': 'Video',
                            },
                          ],
                        },
                      ],
                    },
                  },
                },
              },
            },
          },
        ),
      );
      final submission = store.state.calendarState.days.values.single.hours
          .single.lessonContents.single.submissions.single;
      expect(submission.isLink, isTrue);
      expect(submission.link, 'https://example.org/video');
    });
  });

  group('parseExternalLink', () {
    test('accepts web addresses, with or without a scheme', () {
      expect(parseExternalLink('https://example.org/a?b=1#c').toString(),
          'https://example.org/a?b=1#c');
      expect(parseExternalLink('http://example.org').toString(),
          'http://example.org');
      expect(parseExternalLink(' www.example.org/a ').toString(),
          'https://www.example.org/a');
      expect(parseExternalLink('example.org:8080/a').toString(),
          'https://example.org:8080/a');
    });

    test('rejects everything else', () {
      for (final value in [
        null,
        '',
        '   ',
        'not a link',
        'nothing',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'tel:+390000',
        'ftp://example.org',
        'https://',
        'https://school.it@example.org',
        'https://exa mple.org',
        'https://${'a' * 3000}.org',
      ]) {
        expect(parseExternalLink(value), isNull, reason: '$value');
      }
    });
  });

  group('splitTextLinks', () {
    test('leaves text without a link alone', () {
      expect(splitTextLinks('Seite 3, Nr. 4.'),
          [const TextLinkSegment('Seite 3, Nr. 4.')]);
      expect(splitTextLinks(''), isEmpty);
    });

    test('finds every link, without the punctuation around it', () {
      final segments =
          splitTextLinks('Siehe https://a.org/x. (www.b.org/y), dann Ende');
      expect(segments.where((s) => s.uri != null).map((s) => s.text),
          ['https://a.org/x', 'www.b.org/y']);
      expect(segments.map((s) => s.text).join(),
          'Siehe https://a.org/x. (www.b.org/y), dann Ende');
    });

    test('keeps brackets that are part of the address', () {
      expect(
        splitTextLinks('https://a.org/x_(y)').single.text,
        'https://a.org/x_(y)',
      );
    });

    test('a malformed address stays text', () {
      expect(splitTextLinks('https://a b').every((s) => s.uri == null), isTrue);
      expect(
          splitTextLinks('max@www.b.org').every((s) => s.uri == null), isTrue);
    });
  });

  group('openExternalLink', () {
    tearDown(() => externalLinkLauncherOverride = null);

    test('opens valid links and nothing else', () async {
      final opened = <Uri>[];
      externalLinkLauncherOverride = (uri) async {
        opened.add(uri);
        return true;
      };

      expect(await openExternalLink('www.example.org'), isTrue);
      expect(await openExternalLink('javascript:alert(1)'), isFalse);
      expect(opened, [Uri.parse('https://www.example.org')]);
    });

    test('a launcher that fails is reported, not thrown', () async {
      externalLinkLauncherOverride = (_) => throw StateError('no browser');
      expect(await openExternalLink('https://example.org'), isFalse);
    });
  });

  group('widgets', () {
    tearDown(() => externalLinkLauncherOverride = null);

    testWidgets('a link attachment shows where it leads and opens',
        (tester) async {
      final opened = <GradeGroupSubmission>[];
      final link = _link('https://example.org/worksheet');
      await tester.pumpWidget(_app(AttachmentWidget(
        ggs: link,
        noInternet: true,
        openCallback: opened.add,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Arbeitsblatt'), findsOneWidget);
      expect(find.text('example.org'), findsOneWidget);
      expect(find.byIcon(Icons.link_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.open_in_new_rounded));
      expect(opened, [link]);
    });

    testWidgets('a malformed link is shown but cannot be opened',
        (tester) async {
      await tester.pumpWidget(_app(AttachmentWidget(
        ggs: _link('javascript:alert(1)'),
        noInternet: false,
        openCallback: (_) => fail('must not open'),
      )));
      await tester.pumpAndSettle();

      expect(find.text('javascript:alert(1)'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.byWidgetPredicate((widget) => widget is TextButton),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a link in a text can be tapped', (tester) async {
      final opened = Completer<Uri>();
      externalLinkLauncherOverride = (uri) async {
        opened.complete(uri);
        return true;
      };
      await tester.pumpWidget(_app(
        const LinkifiedText('Lies https://example.org/a bis morgen'),
      ));
      await tester.pumpAndSettle();

      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      final spans = text.textSpan!.children!.cast<TextSpan>();
      expect(spans.map((span) => span.text),
          ['Lies ', 'https://example.org/a', ' bis morgen']);
      (spans[1].recognizer! as TapGestureRecognizer).onTap!();

      expect(await opened.future, Uri.parse('https://example.org/a'));
    });

    testWidgets('a text without a link stays plain', (tester) async {
      await tester.pumpWidget(_app(const LinkifiedText('Seite 3')));
      await tester.pumpAndSettle();
      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(text.data, 'Seite 3');
    });

    testWidgets('a changed text gets new links', (tester) async {
      await tester.pumpWidget(_app(const LinkifiedText('https://a.org')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_app(const LinkifiedText('https://b.org/c')));
      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(text.textSpan!.toPlainText(), 'https://b.org/c');
    });
  });
}
