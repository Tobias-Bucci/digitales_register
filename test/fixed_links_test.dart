// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

// The fixed links of the app (feedback forms, legal pages, source code, the
// Play Store, the contact address) open through the shared helpers of
// lib/external_links.dart, so a link no app can open tells the user (#146).

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/login_page.dart' show LoginPageViewModel;
import 'package:dr/container/settings_page.dart';
import 'package:dr/external_links.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/legal_links.dart';
import 'package:dr/main.dart' show navigatorKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/platform_adapter.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/ui/about_app_dialog.dart';
import 'package:dr/ui/login_page_content.dart';
import 'package:dr/ui/privacy_data_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support/test_harness.dart';

const _failed = 'This link could not be opened';
const _feedbackForm =
    'https://docs.google.com/forms/d/e/1FAIpQLSdvhDufKHMVh4FzAUj5FiaGUjc8ma1DbD3NkRRHdWr4eE16hg/viewform?usp=pp_url&entry.804572866=';
const _errorForm =
    'https://docs.google.com/forms/d/e/1FAIpQLScTmSAZzj0bjwX_8IHVx9dVTTVrncJJpZo_D20dF7mrnU_zdQ/viewform';
const _fork = 'https://github.com/Tobias-Bucci/digitales_register';
const _original = 'https://github.com/miDeb/digitales_register';
const _storeApp =
    'market://details?id=it.bucci.digitalesregister&showAllReviews=true';
const _storeWeb =
    'https://play.google.com/store/apps/details?id=it.bucci.digitalesregister';
const _contact = 'buccitobias774@gmail.com';

/// The system browser and mail app: records what it is asked to open.
class _FakeLauncher extends UrlLauncherPlatform {
  final launches = <(String, LaunchOptions)>[];

  /// Whether an app opens [url]; null makes the launch throw.
  bool? Function(String url) opens = (_) => true;

  List<String> get urls => [for (final (url, _) in launches) url];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => opens(url) ?? false;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches.add((url, options));
    final opened = opens(url);
    if (opened == null) {
      throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
    }
    return opened;
  }
}

void main() {
  late _FakeLauncher browser;
  late UrlLauncherPlatform realLauncher;

  setUp(() async {
    await bootstrapTestEnvironment();
    realLauncher = UrlLauncherPlatform.instance;
    browser = _FakeLauncher();
    UrlLauncherPlatform.instance = browser;
  });
  tearDown(() async {
    UrlLauncherPlatform.instance = realLauncher;
    isAndroidOverride = null;
    await resetTestState();
  });

  Store<AppState, AppStateBuilder, AppActions> englishStore(
          {bool newDesign = false}) =>
      createStore(
        newDesign: newDesign,
        initialState: AppState(
          (b) => b.settingsState.languageCode = AppLanguage.en.code,
        ),
      );

  Future<void> pumpHome(WidgetTester tester, Widget home) =>
      pumpApp(tester, store: englishStore(), home: home);

  /// Lets the launch finish and the failure message come in.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    if (finder.evaluate().isEmpty) {
      // Further down a list that builds only what is visible.
      await tester.scrollUntilVisible(finder, 200,
          scrollable: find
              .byWidgetPredicate((widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down)
              .last);
    }
    await tester.ensureVisible(finder);
    // Not pumpAndSettle: the settings keep a progress indicator running.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(finder);
    await settle(tester);
  }

  group('shared launcher', () {
    testWidgets(
        'a web address opens in the browser, in a new tab of the web app',
        (tester) async {
      await pumpHome(tester, const Scaffold());

      expect(await openExternalLink('https://example.org/a'), isTrue);
      await settle(tester);

      expect(browser.urls, ['https://example.org/a']);
      final options = browser.launches.single.$2;
      expect(options.mode, PreferredLaunchMode.externalApplication);
      expect(options.webOnlyWindowName, '_blank');
      expect(find.text(_failed), findsNothing);
    });

    for (final (name, opens) in [
      ('reports a failure', false),
      ('throws', null),
    ]) {
      testWidgets('a browser that $name tells the user once', (tester) async {
        browser.opens = (_) => opens;
        await pumpHome(tester, const Scaffold());

        expect(await openExternalLink('https://example.org'), isFalse);
        await settle(tester);

        expect(browser.urls, ['https://example.org']);
        expect(find.text(_failed), findsOneWidget);
      });
    }

    testWidgets('other schemes stay refused without a launch', (tester) async {
      await pumpHome(tester, const Scaffold());

      for (final link in [
        'javascript:alert(1)',
        'file:///etc/hosts',
        'data:text/html,<b>x</b>',
        'intent://scan/#Intent;scheme=zxing;end',
        'mailto:$_contact',
        'market://details?id=x',
        'tel:+390471000000',
      ]) {
        expect(await launchExternalLink(link), isFalse, reason: link);
      }
      expect(await openExternalLink('javascript:alert(1)'), isFalse);
      await settle(tester);

      expect(browser.launches, isEmpty);
      expect(find.text(_failed), findsOneWidget);
    });

    testWidgets('an e-mail is built from the fixed address alone',
        (tester) async {
      await pumpHome(tester, const Scaffold());

      expect(await openMailTo(_contact), isTrue);
      await settle(tester);

      expect(browser.urls, ['mailto:$_contact']);
      final options = browser.launches.single.$2;
      expect(options.mode, PreferredLaunchMode.externalApplication);
      // The browser of the web app decides where a mail link opens.
      expect(options.webOnlyWindowName, isNull);
      expect(find.text(_failed), findsNothing);
    });

    testWidgets('an e-mail no app can start tells the user once',
        (tester) async {
      browser.opens = (_) => false;
      await pumpHome(tester, const Scaffold());

      expect(await openMailTo(_contact), isFalse);
      await settle(tester);

      expect(browser.urls, ['mailto:$_contact']);
      expect(find.text(_failed), findsOneWidget);
    });

    testWidgets('an address that adds to the e-mail is refused',
        (tester) async {
      await pumpHome(tester, const Scaffold());

      for (final address in [
        '$_contact?cc=other@example.org',
        '$_contact,other@example.org',
        '$_contact&body=text',
        'javascript:alert(1)//@example.org',
        ' $_contact',
        '$_contact\n',
        'nobody',
        '',
      ]) {
        expect(await openMailTo(address), isFalse, reason: address);
      }
      await settle(tester);

      expect(browser.launches, isEmpty);
    });

    testWidgets('the Play Store app opens the reviews', (tester) async {
      await pumpHome(tester, const Scaffold());

      expect(await openPlayStoreReviews('it.bucci.digitalesregister'), isTrue);
      await settle(tester);

      expect(browser.urls, [_storeApp]);
      expect(find.text(_failed), findsNothing);
    });

    for (final (name, opens) in [
      ('cannot open the reviews', false),
      ('is missing', null),
    ]) {
      testWidgets('the Play Store website opens if the Store app $name',
          (tester) async {
        browser.opens = (url) => url.startsWith('market:') ? opens : true;
        await pumpHome(tester, const Scaffold());

        expect(
            await openPlayStoreReviews('it.bucci.digitalesregister'), isTrue);
        await settle(tester);

        expect(browser.urls, [_storeApp, _storeWeb]);
        expect(browser.launches.last.$2.webOnlyWindowName, '_blank');
        expect(find.text(_failed), findsNothing);
      });
    }

    testWidgets('neither the Store app nor the website tells the user once',
        (tester) async {
      browser.opens = (_) => false;
      await pumpHome(tester, const Scaffold());

      expect(await openPlayStoreReviews('it.bucci.digitalesregister'), isFalse);
      await settle(tester);

      expect(browser.urls, [_storeApp, _storeWeb]);
      expect(find.text(_failed), findsOneWidget);
    });
  });

  group('places', () {
    Future<void> useLargeSurface(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    /// Taps each of [links] (label → address) once with a working browser and
    /// once with a failing one: the failure message comes exactly once, and
    /// only for the failure.
    Future<void> checkLinks(
      WidgetTester tester,
      Future<void> Function() open,
      Map<String, String> links, {
      bool prefixOnly = false,
    }) async {
      for (final MapEntry(key: label, value: address) in links.entries) {
        for (final opens in [true, false]) {
          browser
            ..launches.clear()
            ..opens = (_) => opens;
          await open();
          await tapText(tester, label);

          expect(browser.urls, hasLength(1), reason: label);
          if (prefixOnly) {
            expect(browser.urls.single, startsWith(address), reason: label);
          } else {
            expect(browser.urls.single, address, reason: label);
          }
          expect(find.text(_failed), opens ? findsNothing : findsOneWidget,
              reason: '$label, opens: $opens');
          // The next tap starts without the message.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      }
    }

    testWidgets('the about dialog', (tester) async {
      await useLargeSurface(tester);
      await checkLinks(
        tester,
        () => pumpHome(
            tester, const Scaffold(body: AboutAppDialog(version: '1.0.0'))),
        {
          'digitalesregister.it': 'https://digitalesregister.it',
          'Privacy policy': privacyPolicyUrl,
          'How to delete your account and data': deleteAccountUrl,
        },
      );
    });

    testWidgets('the settings', (tester) async {
      await useLargeSurface(tester);
      isAndroidOverride = () => true;
      Future<void> open() =>
          pumpApp(tester, store: englishStore(), home: SettingsPageContainer());
      await checkLinks(tester, open, {
        'Privacy policy': privacyPolicyUrl,
        'How to delete your account and data': deleteAccountUrl,
        'View source code (fork)': _fork,
        'View original source code': _original,
      });
      await checkLinks(tester, open, {'Send feedback': _feedbackForm},
          prefixOnly: true);
    });

    testWidgets('the settings: Play Store reviews', (tester) async {
      await useLargeSurface(tester);
      isAndroidOverride = () => true;
      browser.opens = (_) => false;
      await pumpApp(tester,
          store: englishStore(), home: SettingsPageContainer());

      await tapText(tester, 'Rate on Google Play Store');

      expect(browser.urls, [_storeApp, _storeWeb]);
      expect(find.text(_failed), findsOneWidget);
    });

    testWidgets('the login page', (tester) async {
      await useLargeSurface(tester);
      Future<void> open() => pumpApp(
            tester,
            store: englishStore(),
            home: LoginPageContent(
              vm: LoginPageViewModel.from(AppState()),
              onLogin: (_, __, ___) {},
              onChangePass: (_, __, ___, ____) {},
              setSaveNoPass: (_) {},
              onReload: () {},
              onRequestPassReset: (_) {},
              onSelectAccount: (_) {},
              onRemoveAccount: (_) {},
            ),
          );
      // The legal links are buttons with a full tap target (#171).
      await checkLinks(
          tester,
          open,
          {
            'Send feedback': _feedbackForm,
            'Privacy': privacyPolicyUrl,
            'Data deletion': deleteAccountUrl,
          },
          prefixOnly: true);
      for (final label in ['Privacy', 'Data deletion']) {
        await open();
        final button = find.ancestor(
            of: find.text(label), matching: find.byType(TextButton));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48),
            reason: label);
        expect(tester.getSize(button).width, greaterThanOrEqualTo(48),
            reason: label);
      }
    });

    // Both designs of the page call the same two handlers; outside the shell
    // of the new design the page shows its Legacy look.
    testWidgets('the privacy details', (tester) async {
      await useLargeSurface(tester);
      await checkLinks(
        tester,
        () => pumpHome(tester, const PrivacyDataDetailsPage()),
        {
          _contact: 'mailto:$_contact',
          'Firebase privacy and data processing':
              'https://firebase.google.com/support/privacy',
        },
      );
    });

    testWidgets('the error page of the error middleware', (tester) async {
      for (final opens in [true, false]) {
        browser
          ..launches.clear()
          ..opens = (_) => opens;
        final store = Store<AppState, AppStateBuilder, AppActions>(
          appReducerBuilder.build(),
          AppState((b) => b
            ..settingsState.languageCode = AppLanguage.en.code
            ..settingsState.legacyDesign = true),
          AppActions(),
          middleware: middleware(),
        );
        addTearDown(store.dispose);
        await pumpApp(tester, store: store, home: const Scaffold());

        store.actions.error(StateError('test'));
        await tester.pumpAndSettle();
        await tapText(tester, 'Contact developer');

        expect(browser.urls, [_errorForm]);
        expect(find.text(_failed), opens ? findsNothing : findsOneWidget,
            reason: 'opens: $opens');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    });

    testWidgets('the page for other account types', (tester) async {
      for (final opens in [true, false]) {
        browser
          ..launches.clear()
          ..opens = (_) => opens;
        await pumpHome(tester, const Scaffold());

        showUserTypeNotSupported('https://school.example.org');
        await tester.pumpAndSettle();
        await tapText(tester, 'Go to the website');

        expect(browser.urls, ['https://school.example.org']);
        expect(find.text(_failed), opens ? findsNothing : findsOneWidget,
            reason: 'opens: $opens');
        navigatorKey!.currentState!.pop();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    });
  });
}
