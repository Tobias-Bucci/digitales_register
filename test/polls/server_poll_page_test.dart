import 'dart:async';
import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show nestedNavKey;
import 'package:dr/polls/poll_api.dart';
import 'package:dr/polls/poll_models.dart';
import 'package:dr/polls/poll_storage.dart';
import 'package:dr/polls/server_polls.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/polls/server_poll_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../server_notifications/support.dart';
import '../support/test_harness.dart';
import 'poll_storage_test.dart' show MemoryPollStorage;

const _optionA = 'b1f4c2d6-0a3e-4f57-8c19-2d6e7f8a9b0c';
const _optionB = 'c8e2a4f6-1b3d-4a5c-9e7f-0a1b2c3d4e5f';

ServerPoll _poll({bool showResults = true}) {
  final json = ((fixture('list-poll')['notifications'] as List).single
      as Map)['poll'] as Map<String, dynamic>;
  json['show_results'] = showResults;
  return ServerPoll.tryParse(json)!;
}

Map<String, dynamic> _state(String name, {bool? showResults}) {
  final json = fixture(name);
  if (showResults != null) {
    (json['poll'] as Map)['show_results'] = showResults;
    if (!showResults) json['results'] = null;
  }
  return json;
}

/// A poll server that answers from a queue, and a device storage.
class _Fixture {
  _Fixture({List<http.Response>? replies, MemoryPollStorage? storage})
      : storage = storage ?? MemoryPollStorage(),
        replies = replies ?? [];

  final MemoryPollStorage storage;
  final List<http.Response> replies;
  final List<http.Request> requests = [];

  late final ServerPolls polls = ServerPolls(
    api: PollApi(
      baseUri: baseUri,
      client: MockClient((request) async {
        requests.add(request);
        if (replies.isEmpty) return http.Response('', 503);
        return replies.removeAt(0);
      }),
    ),
    storage: storage,
    language: () => 'de',
    now: () => DateTime.utc(2026, 11, 16, 9),
  );

  List<http.Request> get votes =>
      requests.where((r) => r.method == 'POST').toList();
}

Future<void> _settle(WidgetTester tester) =>
    settleFor(tester, duration: const Duration(milliseconds: 600));

Future<void> _pump(
  WidgetTester tester,
  _Fixture fixture, {
  required bool newDesign,
  ServerPoll? poll,
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(412, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final page = ServerPollPage(poll: poll ?? _poll(), polls: fixture.polls);
  if (newDesign) {
    final store = createStore(
      initialState: AppState((b) {
        b.dashboardState.allDays = ListBuilder<Day>();
        b.loginState
          ..loggedIn = true
          ..username = 'anna';
      }),
      newDesign: true,
    );
    await pumpApp(tester,
        store: store, home: DaysContainer(), themeMode: themeMode);
    await _settle(tester);
    unawaited(nestedNavKey.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => page)));
  } else {
    // Legacy, and also what a signed-out user sees.
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('de'),
      theme: ThemeData(colorScheme: AppPalette.light),
      darkTheme: ThemeData(colorScheme: AppPalette.dark),
      themeMode: themeMode,
      home: page,
    ));
  }
  await _settle(tester);
}

Future<void> _choose(WidgetTester tester, String optionId) async {
  final tile = find.byKey(ValueKey('poll-option-$optionId'));
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await _settle(tester);
}

Future<void> _voteAndConfirm(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('poll-vote')));
  await tester.tap(find.byKey(const Key('poll-vote')));
  await _settle(tester);
  expect(find.textContaining('stimmen?'), findsOneWidget);
  await tester.tap(find.byKey(const Key('poll-confirm')));
  await _settle(tester);
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() async {
    await resetTestState();
  });

  for (final newDesign in [false, true]) {
    final design = newDesign ? 'new design' : 'legacy design';

    group(design, () {
      testWidgets('shows the poll and votes after a confirmation',
          (tester) async {
        final f = _Fixture(replies: [
          jsonResponse(_state('poll-open')),
          jsonResponse(fixture('vote-receipt')),
        ]);
        await _pump(tester, f, newDesign: newDesign);

        expect(find.text('Welche Funktion wünschst du dir als Nächstes?'),
            findsOneWidget);
        expect(find.byKey(const Key('poll-hint')), findsOneWidget);
        expect(find.textContaining('Eine Stimme pro Gerät, anonym'),
            findsOneWidget);
        // No result before this device voted.
        expect(find.byKey(const Key('poll-results')), findsNothing);
        expect(newDesign, find.byType(GlassPageHeader).evaluate().isNotEmpty);
        // Reading sent no identifier.
        expect(f.requests.single.method, 'GET');
        expect(f.storage.values[pollInstallationIdKey], isNull);

        final vote = tester
            .widget<ButtonStyleButton>(find.byKey(const Key('poll-vote')));
        expect(vote.onPressed, isNull, reason: 'nothing chosen yet');
        await _choose(tester, _optionB);

        // Cancelling sends nothing.
        await tester.tap(find.byKey(const Key('poll-vote')));
        await _settle(tester);
        await tester.tap(find.byKey(const Key('poll-confirm-cancel')));
        await _settle(tester);
        expect(f.votes, isEmpty);

        await _voteAndConfirm(tester);
        expect(f.votes, hasLength(1));
        final sent = jsonDecode(f.votes.single.body) as Map;
        expect(sent['option_id'], _optionB);
        expect(sent['voter'], f.storage.values[pollInstallationIdKey]);

        expect(find.text('Du hast abgestimmt: Notenrechner'), findsOneWidget);
        expect(find.byKey(const Key('poll-vote')), findsNothing);
        expect(find.byKey(const Key('poll-results')), findsOneWidget);
        expect(
            find.text('7 Stimmen. Gezählt werden Stimmen pro Gerät, '
                'nicht Personen.'),
            findsOneWidget);
        expect(f.storage.values[pollVotesKey], contains(_optionB));
        // The screen reader lands on the confirmation.
        final voted = find.ancestor(
            of: find.byKey(const Key('poll-voted')),
            matching: find.byType(Focus));
        expect(tester.widget<Focus>(voted.first).focusNode!.hasFocus, isTrue);
      });

      testWidgets('a repeated vote (409) shows the first choice',
          (tester) async {
        final f = _Fixture(replies: [
          jsonResponse(_state('poll-open')),
          jsonResponse(fixture('vote-already-voted-409'), status: 409),
        ]);
        await _pump(tester, f, newDesign: newDesign);
        await _choose(tester, _optionB);
        await _voteAndConfirm(tester);

        expect(find.text('Du hast abgestimmt: Stundenplan-Widget'),
            findsOneWidget);
        expect(find.byKey(const Key('poll-error')), findsNothing);
        expect(f.storage.values[pollVotesKey], contains(_optionA));
      });

      testWidgets('a closed poll shows its final result and no vote',
          (tester) async {
        final f = _Fixture(replies: [jsonResponse(_state('poll-closed'))]);
        await _pump(tester, f, newDesign: newDesign);

        expect(find.byKey(const Key('poll-closed')), findsOneWidget);
        expect(find.textContaining('Beendet am'), findsOneWidget);
        expect(find.byKey(const Key('poll-vote')), findsNothing);
        expect(find.byKey(const Key('poll-results')), findsOneWidget);
        expect(find.textContaining('58 % · 7 Stimmen'), findsOneWidget);
      });

      testWidgets('a poll that hides its result shows none after the vote',
          (tester) async {
        final f = _Fixture(replies: [
          jsonResponse(_state('poll-open', showResults: false)),
          jsonResponse(fixture('vote-receipt')..['results'] = null),
        ]);
        await _pump(tester, f,
            newDesign: newDesign, poll: _poll(showResults: false));
        await _choose(tester, _optionB);
        await _voteAndConfirm(tester);

        expect(find.text('Du hast abgestimmt: Notenrechner'), findsOneWidget);
        expect(find.byKey(const Key('poll-results')), findsNothing);
        expect(find.byKey(const Key('poll-result-hidden')), findsOneWidget);
      });

      testWidgets('an error says "not possible right now" and blocks nothing',
          (tester) async {
        final f = _Fixture(replies: [
          jsonResponse(_state('poll-open')),
          jsonResponse(fixture('error-rate-limited'), status: 429),
        ]);
        await _pump(tester, f, newDesign: newDesign);
        await _choose(tester, _optionA);
        await _voteAndConfirm(tester);

        expect(find.byKey(const Key('poll-error')), findsOneWidget);
        expect(find.textContaining('Abstimmen ist gerade nicht möglich'),
            findsOneWidget);
        expect(find.byKey(const Key('poll-voted')), findsNothing);
        // The choice stays, and voting can be tried again.
        final vote = tester
            .widget<ButtonStyleButton>(find.byKey(const Key('poll-vote')));
        expect(vote.onPressed, isNotNull);
        expect(f.storage.values[pollVotesKey], isNull);
      });

      testWidgets('a vote of this device is shown offline and after a restart',
          (tester) async {
        final storage = MemoryPollStorage()
          ..values[pollVotesKey] = jsonEncode({_poll().id: _optionB});
        // The server cannot be reached.
        final f = _Fixture(storage: storage);
        await _pump(tester, f, newDesign: newDesign);

        expect(find.text('Du hast abgestimmt: Notenrechner'), findsOneWidget);
        expect(find.byKey(const Key('poll-stale')), findsOneWidget);
        expect(f.votes, isEmpty);
      });

      testWidgets('unreadable storage still lets the poll show',
          (tester) async {
        final f = _Fixture(
          storage: MemoryPollStorage()
            ..failReads = true
            ..failWrites = true,
          replies: [jsonResponse(_state('poll-open'))],
        );
        await _pump(tester, f, newDesign: newDesign);
        expect(find.byKey(const Key('poll-vote')), findsOneWidget);

        await _choose(tester, _optionA);
        await _voteAndConfirm(tester);
        // No ID can be kept, so no vote is sent: it could be repeated.
        expect(f.votes, isEmpty);
        expect(find.byKey(const Key('poll-error')), findsOneWidget);
      });

      testWidgets('a deleted poll cannot be voted', (tester) async {
        final f = _Fixture(replies: [jsonResponse({}, status: 404)]);
        await _pump(tester, f, newDesign: newDesign);
        expect(find.text('Diese Umfrage ist nicht mehr verfügbar.'),
            findsOneWidget);
        expect(find.byKey(const Key('poll-vote')), findsNothing);
      });

      testWidgets('dark theme on a tablet, with labels for screen readers',
          (tester) async {
        final semantics = tester.ensureSemantics();
        final f = _Fixture(replies: [
          jsonResponse(_state('poll-open')),
          jsonResponse(fixture('vote-receipt')),
        ]);
        await _pump(tester, f,
            newDesign: newDesign,
            themeMode: ThemeMode.dark,
            size: const Size(1024, 768));
        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel('Notenrechner'), findsOneWidget);
        await _choose(tester, _optionB);
        await _voteAndConfirm(tester);
        expect(find.bySemanticsLabel('Notenrechner: 43 Prozent, 3 Stimmen'),
            findsOneWidget);
        semantics.dispose();
      });
    });
  }
}
