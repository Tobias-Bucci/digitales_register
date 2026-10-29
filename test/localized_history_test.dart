import 'package:built_collection/built_collection.dart';
import 'package:dr/actions/messages_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/grades_chart_container.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/days.dart';
import 'package:dr/ui/messages.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fixtures.dart';
import 'support/test_harness.dart';

// Monday 12 October 2026.
final _seen = UtcDateTime(2026, 10, 12, 10, 5);
final _sameDayBefore = UtcDateTime(2026, 10, 12, 8, 30);
final _dayBefore = UtcDateTime(2026, 10, 11, 18, 0);

Homework _created({UtcDateTime? lastNotSeen}) =>
    buildHomework(firstSeen: _seen).rebuild((b) => b.lastNotSeen = lastNotSeen);

Homework _changed() =>
    _created(lastNotSeen: _sameDayBefore).rebuild((b) => b.previousVersion
        .replace(buildHomework(firstSeen: _dayBefore, lastNotSeen: null)));

Homework _deleted() =>
    _created(lastNotSeen: _dayBefore).rebuild((b) => b.deleted = true);

Homework _restored() =>
    _created(lastNotSeen: _dayBefore).rebuild((b) => b.previousVersion
        .replace(buildHomework(firstSeen: _dayBefore, deleted: true)));

Message _replied(String response, {String? history}) =>
    buildMessage().rebuild((b) => b
      ..needsResponse = false
      ..showReply = false
      ..badge = response
      ..historyString = history);

void main() {
  final l10n = <AppLanguage, AppLocalizations>{};

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
    for (final language in AppLanguage.values) {
      l10n[language] = await AppLocalizations.load(language.locale);
    }
  });

  group('dashboard history', () {
    test('German output keeps the previous wording', () {
      final de = l10n[AppLanguage.de]!;
      expect(formatChanged(de, _created()),
          'Vor Montag, 12.10, 10:05, eingetragen.');
      expect(formatChanged(de, _changed()),
          'Am Montag, 12.10, zwischen 08:30 und 10:05 geändert.');
      expect(formatChanged(de, _deleted()),
          'Zwischen Sonntag, 11.10, 18:00, und Montag, 12.10, 10:05, gelöscht.');
      expect(
          formatChanged(de, _restored()),
          'Zwischen Sonntag, 11.10, 18:00, und Montag, 12.10, 10:05, '
          'wiederhergestellt.');
    });

    test('English and Italian use their own words and weekday names', () {
      final en = l10n[AppLanguage.en]!;
      expect(formatChanged(en, _created()),
          'Entered before Monday, 12.10, 10:05.');
      expect(formatChanged(en, _changed()),
          'Changed on Monday, 12.10 between 08:30 and 10:05.');
      expect(formatChanged(en, _deleted()),
          'Deleted between Sunday, 11.10, 18:00 and Monday, 12.10, 10:05.');
      expect(formatChanged(en, _restored()),
          'Restored between Sunday, 11.10, 18:00 and Monday, 12.10, 10:05.');

      final it = l10n[AppLanguage.it]!;
      expect(formatChanged(it, _created()),
          'Inserito prima di lunedì, 12.10, 10:05.');
      expect(formatChanged(it, _changed()),
          'Modificato il lunedì, 12.10 tra le 08:30 e le 10:05.');
    });

    test('Ladin is rendered from the Ladin catalog', () {
      final lld = l10n[AppLanguage.lld]!;
      for (final (homework, word) in [
        (_created(), 'Inserí'),
        (_changed(), 'Mudé'),
        (_deleted(), 'Sodé'),
        (_restored(), 'Ripristiné'),
      ]) {
        final text = formatChanged(lld, homework);
        expect(text, startsWith(word));
        expect(text, isNot(contains('eingetragen')));
        expect(text, isNot(contains('zwischen')));
      }
    });
  });

  group('message reply history', () {
    test('a reply made in the app follows the selected language', () {
      expect(messageHistoryText(l10n[AppLanguage.de]!, _replied('agree')),
          'Mit "Stimme zu" beantwortet.');
      expect(messageHistoryText(l10n[AppLanguage.en]!, _replied('agree')),
          'Answered with "I agree".');
      expect(messageHistoryText(l10n[AppLanguage.it]!, _replied('not_agree')),
          'Risposto con "Non acconsento".');
      expect(messageHistoryText(l10n[AppLanguage.lld]!, _replied('agree')),
          'Respondü cun "Son d\'acorde".');
    });

    test('German confirmations stored by older versions are translated', () {
      final en = l10n[AppLanguage.en]!;
      expect(
          messageHistoryText(
              en, _replied('agree', history: 'Mit "Stimme zu" beantwortet.')),
          'Answered with "I agree".');
      expect(
          messageHistoryText(
              en,
              _replied('not_agree',
                  history: 'Mit "Stimme nicht zu" beantwortet.')),
          'Answered with "I disagree".');
    });

    test('server history stays unchanged and unanswered messages have none',
        () {
      final en = l10n[AppLanguage.en]!;
      const server = 'Am 12.10.2026 von Max Muster bestätigt';
      expect(
          messageHistoryText(en, _replied('agree', history: server)), server);
      expect(messageHistoryText(en, buildMessage()), isNull);
      expect(
          messageHistoryText(
              en,
              buildMessage().rebuild((b) => b
                ..needsResponse = true
                ..badge = 'agree')),
          isNull);
    });

    test('the reducer stores the response instead of German text', () async {
      final store = createStore(
          initialState:
              AppState((b) => b.messagesState.messages = ListBuilder<Message>([
                    buildMessage().rebuild((b) => b
                      ..needsResponse = true
                      ..showReply = true)
                  ])));
      await store.actions.messagesActions.repliedMessage(
          ReplyMessagePayload(messageId: 25, response: 'not_agree'));
      final message = store.state.messagesState.messages.single;
      expect(message.historyString, isNull);
      expect(message.badge, 'not_agree');
      expect(messageHistoryText(l10n[AppLanguage.en]!, message),
          'Answered with "I disagree".');
      await store.dispose();
    });
  });

  group('rendered labels', () {
    setUp(bootstrapTestEnvironment);
    tearDown(resetTestState);

    for (final (language, label) in [
      (AppLanguage.de, '4. Januar'),
      (AppLanguage.en, 'January 4'),
      (AppLanguage.it, '4 gennaio'),
    ]) {
      testWidgets('chart selection date in ${language.code}', (tester) async {
        await pumpApp(tester,
            store: createStore(
                initialState: buildGradesPageState().rebuild(
                    (b) => b.settingsState.languageCode = language.code)),
            home: const Center(
              child: SizedBox(
                width: 900,
                height: 700,
                child: Material(
                  child: GradesChartContainer(isFullscreen: true),
                ),
              ),
            ));
        await settleFor(tester);
        await tester.tapAt(const Offset(750, 200));
        await tester.pump();
        await settleFor(tester);
        expect(find.text(label), findsOneWidget);
      });
    }

    for (final (language, summary) in [
      (AppLanguage.de, 'Diagramm | Durchschnitt | 2 ausgeblendet'),
      (AppLanguage.en, 'Chart | Average | 2 hidden'),
      (AppLanguage.it, 'Grafico | Media | 2 nascoste'),
      (AppLanguage.lld, 'Diagram | Media | 2 ascognüdes'),
    ]) {
      testWidgets('grades settings summary in ${language.code}',
          (tester) async {
        tester.view.physicalSize = const Size(1400, 2800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpApp(tester,
            store: createStore(
                initialState: AppState((b) => b.settingsState
                  ..languageCode = language.code
                  ..ignoreForGradesAverage =
                      ListBuilder<String>(['Sport', 'Religion']))),
            home: SettingsPageContainer());
        await settleFor(tester);
        final tile = find.byKey(const Key('settings-grades-tile'));
        for (var i = 0; i < 10 && tile.evaluate().isEmpty; i++) {
          await tester.dragFrom(const Offset(600, 1200), const Offset(0, -400));
          await tester.pumpAndSettle();
        }
        expect(find.descendant(of: tile, matching: find.text(summary)),
            findsOneWidget);
      });
    }
  });
}
