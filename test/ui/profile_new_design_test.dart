import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show nestedNavKey;
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/change_email.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/profile.dart';
import 'package:dr/ui/profile_avatar.dart';
import 'package:dr/ui/profile_new.dart';
import 'package:dr/ui/readable_content.dart';
import 'package:dr/ui/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

const _phone = Size(412, 900);
const _url = 'https://franziskanergymnasium.digitalesregister.it';

ProfileState _full() => ProfileState((b) => b
  ..name = 'Anna Muster'
  ..username = 'anna.muster'
  ..roleName = 'Schüler'
  ..email = 'anna.muster@example.com'
  ..sendNotificationEmails = true);

AppState _state({String languageCode = 'de'}) => AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna.muster';
      b.settingsState.languageCode = languageCode;
      b.url = _url;
    });

/// What a [Profile] passed to its callbacks.
class _Calls {
  final notificationEmails = <bool>[];
  final taxIds = <String>[];
  int changeEmail = 0, changePass = 0, upload = 0;
}

Profile _profile(
  ProfileState profile, {
  _Calls? calls,
  bool noInternet = false,
  Future<void> Function()? upload,
}) =>
    Profile(
      profileState: profile,
      baseUrl: _url,
      noInternet: noInternet,
      biometricAppLockEnabled: false,
      setSendNotificationEmails: (value) =>
          calls?.notificationEmails.add(value),
      setBiometricAppLockEnabled: (_) {},
      changeEmail: () => calls?.changeEmail++,
      changePass: () => calls?.changePass++,
      uploadProfilePicture: upload ??
          () async {
            calls?.upload++;
          },
      updateCodiceFiscale: (value) async => calls?.taxIds.add(value),
    );

/// Opens [page] inside the shell of the new design, as the routing does.
Future<void> _pumpInShell(
  WidgetTester tester,
  Widget page, {
  Size size = _phone,
  ThemeMode themeMode = ThemeMode.light,
  bool amoled = false,
  String languageCode = 'de',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(
    initialState: _state(languageCode: languageCode),
    newDesign: true,
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
  unawaited(nestedNavKey.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => page),
  ));
  await settleFor(tester, duration: const Duration(milliseconds: 600));
}

Finder _key(String key) => find.byKey(Key(key));

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  group('design switch', () {
    testWidgets('the new view inside the shell', (tester) async {
      await _pumpInShell(tester, _profile(_full()));

      expect(find.byType(ProfileNewView), findsOneWidget);
      expect(find.byType(UserProfile), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(NewDesignReadable), findsNothing);
      expect(_key('profile-app-header'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('legacy keeps the app bar, the cards and the figure',
        (tester) async {
      await pumpApp(tester, store: createStore(), home: _profile(_full()));
      await settleFor(tester);

      expect(find.byType(ProfileNewView), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(UserProfile), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
      expect(find.byKey(ProfileAvatar.figureKey), findsOneWidget);
      expect(find.byKey(ProfileAvatar.initialsKey), findsNothing);
    });

    testWidgets('change email: new view in the shell, legacy outside',
        (tester) async {
      await _pumpInShell(tester, ChangeEmail(changeEmail: (_, __) {}));
      expect(find.byType(ChangeEmailNewView), findsOneWidget);
      expect(_key('change-email-app-header'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await pumpApp(
        tester,
        store: createStore(),
        home: ChangeEmail(changeEmail: (_, __) {}),
      );
      await settleFor(tester);
      expect(find.byType(ChangeEmailNewView), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });
  });

  group('content', () {
    testWidgets('identity card with the avatar of the navigation',
        (tester) async {
      await _pumpInShell(tester, _profile(_full()));

      final card = _key('profile-identity');
      expect(tester.widget(card), isA<GlassCard>());
      expect(
        find.descendant(of: card, matching: find.byType(ProfileAvatar)),
        findsOneWidget,
      );
      expect(find.byKey(ProfileAvatar.initialsKey), findsWidgets);
      expect(find.text('Anna Muster'), findsOneWidget);
      expect(find.text('Schüler/in · anna.muster'), findsOneWidget);
      expect(find.text('Franziskanergymnasium Bozen'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('profile-change-email'),
          matching: find.text('anna.muster@example.com'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('every action reaches its callback', (tester) async {
      final calls = _Calls();
      await _pumpInShell(tester, _profile(_full(), calls: calls));

      await tester.tap(_key('profile-upload-picture'));
      await tester.pump();
      await tester.tap(_key('profile-change-email'));
      await tester.tap(_key('profile-change-password'));
      await tester.scrollUntilVisible(_key('profile-notification-emails'), 200,
          scrollable: find
              .descendant(
                  of: _key('profile-list'), matching: find.byType(Scrollable))
              .first);
      await tester.tap(_key('profile-notification-emails'));
      await tester.pump();
      expect(calls.upload, 1);
      expect(calls.changeEmail, 1);
      expect(calls.changePass, 1);
      expect(calls.notificationEmails, [false]);

      await tester.scrollUntilVisible(_key('profile-save-tax-id'), 200,
          scrollable: find
              .descendant(
                  of: _key('profile-list'), matching: find.byType(Scrollable))
              .first);
      expect(tester.widget<FilledButton>(_key('profile-save-tax-id')).enabled,
          isFalse);
      await tester.enterText(
          _key('profile-tax-id-field'), ' rssmra80a01h501u ');
      await tester.pump();
      expect(tester.widget<FilledButton>(_key('profile-save-tax-id')).enabled,
          isTrue);
      await tester.tap(_key('profile-save-tax-id'));
      await tester.pump();
      expect(calls.taxIds, ['RSSMRA80A01H501U']);
    });

    testWidgets('the upload shows that it is running', (tester) async {
      final upload = Completer<void>();
      await _pumpInShell(
        tester,
        _profile(_full(), upload: () => upload.future),
      );

      await tester.tap(_key('profile-upload-picture'));
      await tester.pump();
      expect(find.text('Profilbild wird hochgeladen...'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(_key('profile-upload-picture')).enabled,
        isFalse,
      );
      upload.complete();
      await tester.pump();
      expect(find.text('Profilbild hochladen'), findsOneWidget);
    });

    testWidgets('a locked codice fiscale has no save button', (tester) async {
      await _pumpInShell(
        tester,
        _profile(_full().rebuild((b) => b.codiceFiscale = 'RSSMRA80A01H501U')),
      );

      expect(_key('profile-save-tax-id'), findsNothing);
      expect(
        tester.widget<TextField>(_key('profile-tax-id-field')).readOnly,
        isTrue,
      );
    });

    testWidgets('the sections have headings for screen readers',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpInShell(tester, _profile(_full()));

      expect(find.byType(GlassSectionHeading), findsNWidgets(3));
      expect(
        tester.getSemantics(_key('profile-header-title')),
        isSemantics(label: 'Profil', isHeader: true),
      );
      expect(
        tester.getSemantics(find.descendant(
          of: _key('profile-change-email'),
          matching: find.byType(InkWell),
        )),
        isSemantics(
          label: 'Email-Adresse ändern, anna.muster@example.com',
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });
  });

  group('missing fields', () {
    final cases = <String, ProfileState>{
      'only a name': ProfileState((b) => b..name = 'Max Rossi'),
      'only a user name': ProfileState((b) => b..username = 'max.rossi'),
      'blank name': ProfileState((b) => b
        ..name = '  '
        ..username = 'max.rossi'),
      'no email and no role': ProfileState((b) => b
        ..name = 'Max Rossi'
        ..username = 'max.rossi'),
      'a role only beside the name': ProfileState((b) => b
        ..name = 'Max Rossi'
        ..roleName = 'Eltern'),
    };
    for (final MapEntry(key: label, value: profile) in cases.entries) {
      testWidgets(label, (tester) async {
        await _pumpInShell(tester, _profile(profile));

        expect(tester.takeException(), isNull);
        expect(_key('profile-identity'), findsOneWidget);
        expect(_key('profile-name'), findsOneWidget);
        final name = tester.widget<Text>(_key('profile-name')).data!;
        expect(name.trim(), isNotEmpty);
        // No empty line below the name.
        for (final text in tester.widgetList<Text>(find.descendant(
          of: _key('profile-identity'),
          matching: find.byType(Text),
        ))) {
          expect(text.data?.trim(), isNot(isEmpty));
        }
        expect(_key('profile-change-email'), findsOneWidget);
      });
    }

    testWidgets('nothing yet: a loading card, not an empty one',
        (tester) async {
      await _pumpInShell(tester, _profile(ProfileState()));

      expect(_key('profile-loading'), findsOneWidget);
      expect(_key('profile-identity'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('states', () {
    testWidgets('offline without a profile', (tester) async {
      await _pumpInShell(tester, _profile(ProfileState(), noInternet: true));

      expect(_key('profile-offline'), findsOneWidget);
      expect(find.text('Keine Verbindung'), findsOneWidget);
    });

    testWidgets('offline, the actions that need the server are off',
        (tester) async {
      final calls = _Calls();
      await _pumpInShell(
        tester,
        _profile(_full(), calls: calls, noInternet: true),
      );

      expect(
        tester.widget<FilledButton>(_key('profile-upload-picture')).enabled,
        isFalse,
      );
      expect(tester.widget<GlassTile>(_key('profile-change-email')).enabled,
          isFalse);
      await tester.tap(_key('profile-change-email'));
      await tester.tap(_key('profile-change-password'));
      expect(calls.changeEmail + calls.changePass, 0);
      final notifications = tester.widget<SwitchListTile>(find.descendant(
        of: _key(
          'profile-notification-emails',
        ),
        matching: find.byType(SwitchListTile),
      ));
      expect(notifications.onChanged, isNull);
    });
  });

  group('layouts', () {
    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('phone, ${themeMode.name}', (tester) async {
        await _pumpInShell(tester, _profile(_full()),
            size: const Size(360, 640), themeMode: themeMode);

        final header = tester.getRect(_key('profile-app-header'));
        expect(header.left, 0);
        expect(tester.getRect(_key('profile-identity')).top,
            greaterThanOrEqualTo(header.bottom));
        expect(tester.takeException(), isNull);
      });

      testWidgets('wide window, ${themeMode.name}', (tester) async {
        await _pumpInShell(tester, _profile(_full()),
            size: const Size(1280, 800), themeMode: themeMode);

        final card = tester.getRect(_key('profile-identity'));
        expect(card.width, lessThanOrEqualTo(DesignTokens.contentMaxWidth));
        // The picture stands beside the name.
        final avatar = tester.getRect(find.descendant(
          of: _key('profile-identity'),
          matching: find.byType(ProfileAvatar),
        ));
        expect(
            avatar.right, lessThan(tester.getRect(_key('profile-name')).left));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('AMOLED', (tester) async {
      await _pumpInShell(tester, _profile(_full()),
          themeMode: ThemeMode.dark, amoled: true);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the list ends above the floating bar', (tester) async {
      await _pumpInShell(tester, _profile(_full()), size: const Size(360, 500));

      await tester.fling(
        find
            .descendant(
                of: _key('profile-list'), matching: find.byType(Scrollable))
            .first,
        const Offset(0, -3000),
        3000,
      );
      await settleFor(tester);
      expect(
        tester.getRect(_key('profile-tax-id')).bottom,
        lessThanOrEqualTo(tester.getTopLeft(_key('app-navigation-bar')).dy),
      );
    });

    for (final page in ['profile', 'change email']) {
      testWidgets('$page at 320 px with text at 200 %', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pumpInShell(
          tester,
          page == 'profile'
              ? _profile(_full())
              : ChangeEmail(changeEmail: (_, __) {}),
          size: const Size(320, 640),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('glass', () {
    testWidgets('only the header blurs', (tester) async {
      await _pumpInShell(tester, _profile(_full()));

      expect(
        find.descendant(
          of: _key('profile-list'),
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
      await _pumpInShell(tester, _profile(_full()));

      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ProfileNewView),
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
      await _pumpInShell(tester, _profile(_full()));

      expect(find.byType(ProfileNewView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('back navigation', () {
    for (final page in ['profile', 'change email']) {
      testWidgets('the back button closes $page', (tester) async {
        await _pumpInShell(
          tester,
          page == 'profile'
              ? _profile(_full())
              : ChangeEmail(changeEmail: (_, __) {}),
        );

        await tester.tap(find.byType(BackButton));
        await settleFor(tester, duration: const Duration(milliseconds: 600));
        expect(find.byType(Profile), findsNothing);
        expect(find.byType(ChangeEmail), findsNothing);
      });
    }
  });

  group('change email', () {
    testWidgets('nothing is sent while a field is wrong', (tester) async {
      final sent = <(String, String)>[];
      await _pumpInShell(
        tester,
        ChangeEmail(changeEmail: (pass, email) => sent.add((pass, email))),
      );

      await tester.tap(_key('change-email-submit'));
      await tester.pump();
      expect(find.text('Bitte gib etwas ein'), findsNWidgets(2));

      await tester.enterText(_key('change-email-password'), 'secret');
      await tester.enterText(_key('change-email-address'), 'anna@example');
      await tester.tap(_key('change-email-submit'));
      await tester.pump();
      expect(
        find.text('Bitte gib eine gültige Email-Adresse ein'),
        findsOneWidget,
      );
      expect(sent, isEmpty);
    });

    testWidgets('a valid form is sent and shows that it waits', (tester) async {
      final answer = Completer<void>();
      final sent = <(String, String)>[];
      await _pumpInShell(
        tester,
        ChangeEmail(changeEmail: (pass, email) {
          sent.add((pass, email));
          return answer.future;
        }),
      );

      await tester.enterText(_key('change-email-password'), 'secret');
      await tester.enterText(
          _key('change-email-address'), 'anna.neu@example.com');
      await tester.tap(_key('change-email-submit'));
      await tester.pump();
      expect(sent, [('secret', 'anna.neu@example.com')]);
      final submit = find.descendant(
        of: _key('change-email-submit'),
        matching: find.byType(CircularProgressIndicator),
      );
      expect(submit, findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.descendant(
              of: _key('change-email-password'),
              matching: find.byType(TextField),
            ))
            .enabled,
        isFalse,
      );

      // A second tap while waiting sends nothing.
      await tester.tap(_key('change-email-submit'), warnIfMissed: false);
      await tester.pump();
      expect(sent, hasLength(1));

      answer.complete();
      await tester.pump();
      expect(submit, findsNothing);
      expect(
        tester
            .widget<TextField>(find.descendant(
              of: _key('change-email-password'),
              matching: find.byType(TextField),
            ))
            .enabled,
        isTrue,
      );
    });

    testWidgets('the password can be shown', (tester) async {
      await _pumpInShell(tester, ChangeEmail(changeEmail: (_, __) {}));
      TextField field() => tester.widget<TextField>(find.descendant(
            of: _key('change-email-password'),
            matching: find.byType(TextField),
          ));

      expect(field().obscureText, isTrue);
      await tester.tap(find.byTooltip('Passwort anzeigen'));
      await tester.pump();
      expect(field().obscureText, isFalse);
    });

    testWidgets('the save button stays above the keyboard on a small phone',
        (tester) async {
      await _pumpInShell(tester, ChangeEmail(changeEmail: (_, __) {}),
          size: const Size(360, 640));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.showKeyboard(_key('change-email-address'));
      await settleFor(tester, duration: const Duration(milliseconds: 600));

      expect(
        tester.getRect(_key('change-email-submit')).bottom,
        lessThanOrEqualTo(640 - 300),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('languages', () {
    for (final code in ['de', 'it', 'en', 'lld']) {
      testWidgets('in $code', (tester) async {
        await _pumpInShell(tester, _profile(_full()),
            languageCode: code, size: const Size(320, 640));
        final l10n = tester.element(find.byType(ProfileNewView)).l10n;
        expect(
          tester.widget<Text>(_key('profile-header-title')).data,
          l10n.text('profile.title'),
        );
        expect(find.text(l10n.text('profile.changeEmail')), findsOneWidget);
        expect(
          l10n.text('changeEmail.invalidEmail'),
          isNot('changeEmail.invalidEmail'),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
