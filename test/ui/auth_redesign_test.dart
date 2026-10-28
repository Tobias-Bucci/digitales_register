import 'dart:io';
import 'dart:ui' as ui;

import 'package:dr/app_state.dart';
import 'package:dr/config.dart';
import 'package:dr/container/login_page.dart' show LoginPageViewModel;
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/auth_layout.dart';
import 'package:dr/ui/login_page_content.dart';
import 'package:dr/ui/pass_reset.dart';
import 'package:dr/ui/request_pass_reset.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

LoginPageContent login({
  AppState? state,
  LoginCallback? onLogin,
  void Function(String, String, String, String)? onChangePass,
  ValueChanged<bool>? onSafeMode,
  ValueChanged<int>? onSelect,
  ValueChanged<int>? onRemove,
  ValueChanged<String>? onRecovery,
}) =>
    LoginPageContent(
      vm: LoginPageViewModel.from(state ?? AppState()),
      onLogin: onLogin ?? (_, __, ___) {},
      onChangePass: onChangePass ?? (_, __, ___, ____) {},
      setSaveNoPass: onSafeMode ?? (_) {},
      onReload: () {},
      onRequestPassReset: onRecovery ?? (_) {},
      onSelectAccount: onSelect ?? (_) {},
      onRemoveAccount: onRemove ?? (_) {},
    );

Future<void> revealAndTap(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  testWidgets('keyboard submits unchanged credentials and session preference',
      (tester) async {
    List<String>? payload;
    bool? safeMode;
    await pumpApp(tester,
        store: createStore(),
        home: login(
          onLogin: (user, pass, url) => payload = [user, pass, url],
          onSafeMode: (value) => safeMode = value,
        ));
    expect(field('Adresse'), findsNothing);
    await tester.enterText(field('Schule'), 'Unbekannte Schule');
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('Schule nicht gefunden'), findsOneWidget);
    await revealAndTap(tester, find.text('Adresse manuell eingeben'));
    await tester.enterText(
        field('Adresse'), 'https://example.digitalesregister.it');
    await tester.enterText(field('Benutzername'), 'student');
    await tester.enterText(field('Passwort'), '  Exact password!  ');
    bool switchValue() => tester.widget<Switch>(find.byType(Switch)).value;
    final initial = switchValue();
    // The whole row toggles, not only the (scaled-down) switch.
    await revealAndTap(tester, find.text('Angemeldet bleiben'));
    final selected = switchValue();
    expect(selected, !initial);
    await tester.showKeyboard(field('Passwort'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(payload, [
      'student',
      '  Exact password!  ',
      'https://example.digitalesregister.it'
    ]);
    expect(safeMode, !selected);
  });

  testWidgets('sign-in stays disabled until username and password are set',
      (tester) async {
    List<String>? payload;
    await pumpApp(tester,
        store: createStore(),
        home: login(
          onLogin: (user, pass, url) => payload = [user, pass, url],
        ));
    ElevatedButton button() => tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Anmelden'));
    expect(button().onPressed, isNull);
    await tester.enterText(field('Benutzername'), 'student');
    await tester.pump();
    expect(button().onPressed, isNull);
    await tester.showKeyboard(field('Passwort'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(payload, isNull);
    await tester.enterText(field('Passwort'), 'secret');
    await tester.pump();
    expect(button().onPressed, isNotNull);
    await revealAndTap(tester, find.widgetWithText(ElevatedButton, 'Anmelden'));
    expect(payload?.take(2), ['student', 'secret']);
  });

  testWidgets('demo credentials with blank school keep the empty URL contract',
      (tester) async {
    String? url;
    await pumpApp(tester,
        store: createStore(),
        home: login(onLogin: (_, __, value) => url = value));
    await tester.enterText(field('Benutzername'), 'demo');
    await tester.enterText(field('Passwort'), 'demo');
    await revealAndTap(tester, find.widgetWithText(ElevatedButton, 'Anmelden'));
    expect(url, '');
  });

  testWidgets('school search supports keyboard selection and custom address',
      (tester) async {
    String? url;
    await pumpApp(tester,
        store: createStore(), home: login(onRecovery: (value) => url = value));
    final school = schools.entries.first;
    await tester.enterText(field('Schule'), school.key);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(field('Adresse'), findsNothing);
    expect(find.text(Uri.parse(school.value).host), findsOneWidget);
    await revealAndTap(tester, find.text('Passwort vergessen'));
    expect(url, school.value);

    await tester.enterText(field('Schule'), 'zzzzzz');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Andere Schule').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        field('Adresse'), 'https://custom.digitalesregister.it');
    await revealAndTap(tester, find.text('Passwort vergessen'));
    expect(url, 'https://custom.digitalesregister.it');
    expect(find.text('Schule nicht gefunden'), findsNothing);
  });

  testWidgets('password visibility and tab traversal retain typed values',
      (tester) async {
    await pumpApp(tester, store: createStore(), home: login());
    await tester.enterText(field('Passwort'), 'secret');
    expect(tester.widget<TextField>(field('Passwort')).obscureText, isTrue);
    await revealAndTap(tester, find.byTooltip('Passwort anzeigen'));
    expect(tester.widget<TextField>(field('Passwort')).obscureText, isFalse);
    expect(
        tester.widget<TextField>(field('Passwort')).controller!.text, 'secret');
    await revealAndTap(tester, find.byTooltip('Passwort verbergen'));
    expect(tester.widget<TextField>(field('Passwort')).obscureText, isTrue);
    await tester.tap(field('Benutzername'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(
        tester
            .widget<EditableText>(find.descendant(
                of: field('Passwort'), matching: find.byType(EditableText)))
            .focusNode
            .hasFocus,
        isTrue);
  });

  testWidgets('saved account selection and confirmed removal preserve indices',
      (tester) async {
    int? selected, removed;
    await pumpApp(tester,
        store: createStore(),
        home: login(
          state: AppState((b) =>
              b.loginState.otherAccounts.addAll(['student-a', 'parent-b'])),
          onSelect: (value) => selected = value,
          onRemove: (value) => removed = value,
        ));
    await revealAndTap(tester, find.text('parent-b'));
    expect(selected, 1);
    await revealAndTap(tester, find.byTooltip('Konto entfernen').last);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(removed, isNull);
    await revealAndTap(tester, find.byTooltip('Konto entfernen').last);
    await tester.tap(find.widgetWithText(FilledButton, 'Konto entfernen'));
    await tester.pumpAndSettle();
    expect(removed, 1);
  });

  testWidgets('loading disables credential changes and repeated submission',
      (tester) async {
    var submissions = 0;
    await pumpApp(tester,
        store: createStore(),
        home: login(
          state: AppState((b) => b.loginState.loading = true),
          onLogin: (_, __, ___) => submissions++,
        ));
    expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((f) => f.enabled == false),
        isTrue);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .semanticsLabel,
        'Bitte warten …');
    expect(tester.getSize(find.byType(ElevatedButton)).height, 50);
    expect(submissions, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('network failure is announced near the action and permits retry',
      (tester) async {
    var submissions = 0;
    await pumpApp(tester,
        store: createStore(),
        home: login(
          state: AppState((b) => b
            ..url = testServerUrl
            ..noInternet = true
            ..loginState.errorMsg = 'network'),
          onLogin: (_, __, ___) => submissions++,
        ));
    final message = tester.widget<AuthMessage>(find.byType(AuthMessage));
    expect(message.isError, isTrue);
    expect(message.text, contains(testServerUrl));
    await tester.ensureVisible(find.byType(AuthMessage));
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    final messageSemantics = tester.getSemantics(find
        .descendant(
            of: find.byType(AuthMessage), matching: find.byType(Semantics))
        .first);
    expect(messageSemantics.getSemanticsData().flagsCollection.isLiveRegion,
        isTrue);
    semantics.dispose();
    await tester.enterText(field('Benutzername'), 'student');
    await tester.enterText(field('Passwort'), 'secret');
    await revealAndTap(tester, find.widgetWithText(ElevatedButton, 'Anmelden'));
    expect(submissions, 1);
  });

  testWidgets('address appears only for schools outside the list',
      (tester) async {
    await pumpApp(tester, store: createStore(), home: login());
    expect(field('Adresse'), findsNothing);
    expect(find.text('Adresse manuell eingeben'), findsNothing);

    final school = schools.entries.first;
    await tester.enterText(field('Schule'), school.key);
    await tester.pumpAndSettle();
    expect(field('Adresse'), findsNothing);
    expect(find.text(Uri.parse(school.value).host), findsOneWidget);

    await tester.enterText(field('Schule'), 'zzzzzz');
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('Schule nicht gefunden'), findsOneWidget);
    await revealAndTap(tester, find.text('Adresse manuell eingeben'));
    expect(field('Adresse'), findsOneWidget);
    expect(tester.widget<TextField>(field('Schule')).controller!.text,
        'Andere Schule');
    expect(tester.widget<TextField>(field('Adresse')).controller!.text,
        '.digitalesregister.it');
    expect(
        tester
            .widget<EditableText>(find.descendant(
                of: field('Adresse'), matching: find.byType(EditableText)))
            .focusNode
            .hasFocus,
        isTrue);
    expect(find.text('Adresse manuell eingeben'), findsNothing);
  });

  testWidgets('a stored custom address is shown immediately', (tester) async {
    await pumpApp(tester,
        store: createStore(),
        home:
            login(state: AppState((b) => b.url = 'https://custom.example.it')));
    expect(tester.widget<TextField>(field('Adresse')).controller!.text,
        'https://custom.example.it');
  });

  testWidgets('long saved account lists collapse to three rows',
      (tester) async {
    final accounts = ['a.one', 'b.two', 'c.three', 'd.four', 'e.five'];
    int? selected;
    await pumpApp(tester,
        store: createStore(),
        home: login(
          state: AppState((b) => b.loginState.otherAccounts.addAll(accounts)),
          onSelect: (value) => selected = value,
        ));
    expect(find.text('Weitere Konten'), findsOneWidget);
    expect(find.text('d.four'), findsNothing);
    expect(find.byTooltip('Konto entfernen'), findsNWidgets(3));
    await revealAndTap(tester, find.text('2 weitere anzeigen'));
    expect(find.byTooltip('Konto entfernen'), findsNWidgets(5));
    await revealAndTap(tester, find.text('e.five'));
    expect(selected, 4);
    await revealAndTap(tester, find.text('Weniger anzeigen'));
    expect(find.text('e.five'), findsNothing);
  });

  testWidgets('no saved accounts means no account section', (tester) async {
    await pumpApp(tester, store: createStore(), home: login());
    expect(find.text('Weitere Konten'), findsNothing);
  });

  testWidgets('long errors, names and large text fit a small phone',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);
    final state = AppState((b) => b
      ..loginState.errorMsg =
          List.filled(12, 'Sehr lange Fehlermeldung').join(' ')
      ..loginState.username = List.filled(8, 'langer.benutzername').join()
      ..loginState.otherAccounts.add(List.filled(6, 'konto.name').join()));
    await tester.pumpWidget(buildTestApp(
      store: createStore(initialState: state),
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(1.3),
            disableAnimations: true),
        child: login(state: state),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AuthMessage), findsOneWidget);
    for (final finder in [
      find.byType(AuthMessage),
      find.byType(ElevatedButton),
      find.text('Feedback senden'),
    ]) {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      final rect = tester.getRect(finder);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('forced password change preserves mismatch gating and callback',
      (tester) async {
    List<String>? payload;
    await pumpApp(tester,
        store: createStore(),
        home: login(
          state: AppState((b) => b
            ..url = testServerUrl
            ..loginState.changePassword = true
            ..loginState.mustChangePassword = true
            ..loginState.username = 'student'),
          onChangePass: (user, old, value, url) =>
              payload = [user, old, value, url],
        ));
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Du musst dein Passwort ändern.'), findsOneWidget);
    expect(tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
        isFalse);
    await tester.enterText(field('Altes Passwort'), 'old');
    await tester.enterText(field('Neues Passwort'), 'New1234567!');
    await tester.enterText(field('Neues Passwort wiederholen'), 'mismatch');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(payload, isNull);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);
    await tester.enterText(field('Neues Passwort wiederholen'), 'New1234567!');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(payload, ['student', 'old', 'New1234567!', testServerUrl]);
  });

  testWidgets('recovery request and successful link reset keep their actions',
      (tester) async {
    List<String>? request;
    await pumpApp(tester,
        store: createStore(),
        home: RequestPassReset(
          resetPass: (user, email) => request = [user, email],
          failure: true,
          message: 'Serverfehler',
        ));
    await tester.enterText(field('Benutzername'), 'student');
    await tester.enterText(field('Neue Email-Adresse'), 'student@example.com');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(request, ['student', 'student@example.com']);
    expect(
        tester.widget<AuthMessage>(find.byType(AuthMessage)).isError, isTrue);

    String? password;
    var closed = false;
    final key = GlobalKey();
    Widget reset({String? message, bool failure = false}) => PassReset(
        key: key,
        resetPass: (value) => password = value,
        failure: failure,
        message: message,
        onClose: () => closed = true);
    final store = createStore();
    await pumpApp(tester, store: store, home: reset());
    await tester.enterText(field('Neues Passwort'), 'New1234567!');
    await tester.enterText(field('Neues Passwort wiederholen'), 'wrong');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(password, isNull);
    await tester.enterText(field('Neues Passwort wiederholen'), 'New1234567!');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(password, 'New1234567!');
    await pumpApp(tester, store: store, home: reset(message: 'Erfolgreich'));
    expect(find.text('Passwort zurücksetzen'), findsOneWidget); // heading only
    await revealAndTap(tester, find.widgetWithText(ElevatedButton, 'Fertig'));
    expect(closed, isTrue);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('login accessibility guidelines ${mode.name}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 1000);
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      await pumpApp(tester,
          store: createStore(), themeMode: mode, home: login());
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    });
  }

  testWidgets('voluntary password change returns to the previous route',
      (tester) async {
    await pumpApp(tester,
        store: createStore(),
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () {
                        Navigator.of(context).push<void>(MaterialPageRoute(
                            builder: (_) => login(
                                  state: AppState((b) => b.loginState
                                    ..changePassword = true
                                    ..mustChangePassword = false),
                                )));
                      },
                      child: const Text('Open')),
                )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
        isTrue);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.byType(LoginPageContent), findsNothing);
  });

  const layouts = [
    (name: 'small', size: Size(320, 640), scale: 1.0, inset: 0.0),
    (name: 'phone', size: Size(390, 844), scale: 1.0, inset: 0.0),
    (name: 'tablet', size: Size(768, 1024), scale: 1.0, inset: 0.0),
    (name: 'desktop', size: Size(1440, 1000), scale: 1.0, inset: 0.0),
    (
      name: 'landscape-keyboard',
      size: Size(740, 360),
      scale: 1.6,
      inset: 140.0
    ),
    (
      name: 'desktop-large-text',
      size: Size(1440, 1000),
      scale: 2.0,
      inset: 0.0
    ),
  ];
  for (final language in ['de', 'it', 'en', 'lld']) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final layout in layouts) {
        for (final page in ['login', 'change', 'request', 'reset']) {
          testWidgets('$page $language ${mode.name} ${layout.name}',
              (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = layout.size;
            tester.view.viewInsets = FakeViewPadding(bottom: layout.inset);
            addTearDown(tester.view.reset);
            final state = AppState((b) => b
              ..settingsState.languageCode = language
              ..loginState.changePassword = (page == 'change')
              ..loginState.mustChangePassword = (page == 'change')
              ..loginState
                  .otherAccounts
                  .add('Very long saved student account name@example.com'));
            final Widget home = switch (page) {
              'request' => RequestPassReset(
                  resetPass: (_, __) {},
                  failure: true,
                  message: 'Serverfehler'),
              'reset' => PassReset(
                  resetPass: (_) {},
                  failure: false,
                  message: 'Erfolgreich',
                  onClose: () {}),
              _ => login(state: state),
            };
            await tester.pumpWidget(buildTestApp(
              store: createStore(initialState: state),
              themeMode: mode,
              home: MediaQuery(
                data: MediaQueryData(
                    size: layout.size,
                    viewInsets: EdgeInsets.only(bottom: layout.inset),
                    textScaler: TextScaler.linear(layout.scale),
                    disableAnimations: true),
                child: home,
              ),
            ));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final button = find.byType(ElevatedButton).first;
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            final rect = tester.getRect(button);
            expect(rect.width, lessThanOrEqualTo(448));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.bottom,
                lessThanOrEqualTo(layout.size.height - layout.inset + 1));
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }

  testWidgets('export representative rendered previews when requested',
      (tester) async {
    if (Platform.environment['UPDATE_AUTH_PREVIEWS'] != '1') return;
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    await loadPreviewFonts(tester);
    const phone = Size(390, 844);
    const desktop = Size(1280, 800);
    const android = TargetPlatform.android, windows = TargetPlatform.windows;
    final scenarios = [
      (name: 'desktop', size: desktop, os: windows, state: 'login', scale: 1.0),
      (
        name: 'desktop_accounts',
        size: desktop,
        os: windows,
        state: 'accounts',
        scale: 1.0
      ),
      (
        name: 'desktop_school',
        size: desktop,
        os: windows,
        state: 'school',
        scale: 1.0
      ),
      (
        name: 'desktop_narrow',
        size: const Size(420, 700),
        os: windows,
        state: 'login',
        scale: 1.0
      ),
      (name: 'phone', size: phone, os: android, state: 'login', scale: 1.0),
      (
        name: 'phone_school',
        size: phone,
        os: android,
        state: 'school',
        scale: 1.0
      ),
      (
        name: 'phone_custom',
        size: phone,
        os: android,
        state: 'custom',
        scale: 1.0
      ),
      (
        name: 'phone_accounts',
        size: phone,
        os: android,
        state: 'accounts',
        scale: 1.0
      ),
      // Tall enough to show the collapsed account list and the footer.
      (
        name: 'phone_accounts_full',
        size: const Size(390, 1240),
        os: android,
        state: 'accounts',
        scale: 1.0
      ),
      (
        name: 'phone_error',
        size: phone,
        os: android,
        state: 'error',
        scale: 1.0
      ),
      (
        name: 'phone_loading',
        size: phone,
        os: android,
        state: 'loading',
        scale: 1.0
      ),
      (
        name: 'phone_ios',
        size: phone,
        os: TargetPlatform.iOS,
        state: 'login',
        scale: 1.0
      ),
      (
        name: 'landscape',
        size: const Size(844, 390),
        os: android,
        state: 'login',
        scale: 1.0
      ),
      (
        name: 'small',
        size: const Size(360, 640),
        os: android,
        state: 'login',
        scale: 1.0
      ),
      (
        name: 'small_text',
        size: const Size(360, 640),
        os: android,
        state: 'accounts',
        scale: 1.3
      ),
      (name: 'change', size: phone, os: android, state: 'change', scale: 1.0),
      (name: 'request', size: phone, os: android, state: 'request', scale: 1.0),
      (name: 'reset', size: phone, os: android, state: 'reset', scale: 1.0),
      (name: 'success', size: phone, os: android, state: 'success', scale: 1.0),
    ];
    final school = schools.entries.first;
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final scenario in scenarios) {
        final page = scenario.state;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = scenario.size;
        addTearDown(tester.view.reset);
        debugDefaultTargetPlatformOverride = scenario.os;
        final state = AppState((b) {
          b
            ..loginState.changePassword = page == 'change'
            ..loginState.mustChangePassword = page == 'change'
            ..loginState.loading = page == 'loading'
            ..loginState.errorMsg = switch (page) {
              'error' => 'Ungültiger Benutzer/Passwort',
              'accounts' when scenario.name == 'desktop_accounts' =>
                'Die Anmeldung wurde abgelehnt. Prüfe deine Zugangsdaten.',
              _ => null,
            }
            ..loginState.otherAccounts.addAll(page == 'accounts'
                ? [
                    'maria.muster',
                    'max.mustermann@schule.example.it',
                    'eltern.muster',
                    'anna.beispiel',
                    'lukas.beispiel'
                  ]
                : <String>[]);
          if (page == 'school' || page == 'loading') {
            b
              ..url = school.value
              ..loginState.username = 'maria.muster';
          }
          if (page == 'custom') b.url = 'https://meine-schule.example.it';
        });
        final Widget home = switch (page) {
          'request' => RequestPassReset(resetPass: (_, __) {}, failure: false),
          'reset' || 'success' => PassReset(
              resetPass: (_) {},
              failure: false,
              message:
                  page == 'success' ? 'Passwort erfolgreich geändert' : null,
              onClose: () {}),
          _ => login(state: state),
        };
        final boundaryKey = GlobalKey();
        final controller = AppThemeController();
        await tester.pumpWidget(previewApp(
            key: boundaryKey,
            controller: controller,
            mode: mode,
            scale: scenario.scale,
            home: home));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.runAsync(() => precacheImage(
            const AssetImage('assets/Icon-App-512x512.png'),
            tester.element(find.byType(AuthLayout))));
        // A filled form shows the enabled button and unfocused fields.
        if (page == 'school') {
          await tester.enterText(field('Passwort'), 'secret');
          FocusManager.instance.primaryFocus?.unfocus();
        }
        // Fixed pumps: the loading spinner never settles.
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        await capturePreview(
            tester, boundaryKey, '${scenario.name}_${mode.name}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    }
    debugDisableShadows = previousShadows;
  });

  testWidgets('export mid-animation frames when requested', (tester) async {
    if (Platform.environment['UPDATE_AUTH_PREVIEWS'] != '1') return;
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    await loadPreviewFonts(tester);
    // Decode the icon first so the earliest frames are not missing it.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(() => precacheImage(
        const AssetImage('assets/Icon-App-512x512.png'),
        tester.element(find.byType(SizedBox))));
    const entranceMs = 700;
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final target in [
        (name: 'phone', size: const Size(390, 844), os: TargetPlatform.android),
        (
          name: 'desktop',
          size: const Size(1280, 800),
          os: TargetPlatform.windows
        ),
      ]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = target.size;
        addTearDown(tester.view.reset);
        debugDefaultTargetPlatformOverride = target.os;
        final key = GlobalKey();
        final controller = AppThemeController();
        final state = ValueNotifier(AppState());
        await tester.pumpWidget(previewApp(
          key: key,
          controller: controller,
          mode: mode,
          home: ValueListenableBuilder<AppState>(
            valueListenable: state,
            builder: (context, value, _) => login(state: value),
          ),
        ));
        // Entrance at 0, 30, 60 and 100 %. The ticker's first frame has no
        // elapsed time, so the first capture is the true start.
        var elapsed = 0;
        for (final percent in [0, 30, 60, 100]) {
          final at = entranceMs * percent ~/ 100;
          await tester.pump(Duration(milliseconds: at - elapsed));
          elapsed = at;
          await capturePreview(tester, key,
              'frames/${target.name}_entrance_${percent}_${mode.name}');
        }
        await tester.pumpAndSettle();
        // A rejected attempt: the error grows in while the form shakes.
        state.value = AppState((b) => b.loginState.loading = true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        state.value = AppState(
            (b) => b.loginState.errorMsg = 'Ungültiger Benutzer/Passwort');
        await tester.pump();
        elapsed = 0;
        for (final at in [40, 80, 160]) {
          await tester.pump(Duration(milliseconds: at - elapsed));
          elapsed = at;
          await capturePreview(
              tester, key, 'frames/${target.name}_error_${at}_${mode.name}');
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    }
    debugDisableShadows = previousShadows;
  });
  testWidgets('export first-run fit and suggestion previews when requested',
      (tester) async {
    if (Platform.environment['UPDATE_AUTH_PREVIEWS'] != '1') return;
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    await loadPreviewFonts(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(() => precacheImage(
        const AssetImage('assets/Icon-App-512x512.png'),
        tester.element(find.byType(SizedBox))));
    const android = EdgeInsets.only(top: 24, bottom: 48);
    final screens = [
      (
        name: 'fit_392x850',
        size: const Size(392, 850),
        padding: android,
        scale: 1.0,
        accounts: false,
        search: true
      ),
      (
        name: 'fit_390x844',
        size: const Size(390, 844),
        padding: const EdgeInsets.only(top: 47, bottom: 34),
        scale: 1.0,
        accounts: false,
        search: false
      ),
      (
        name: 'fit_360x740',
        size: const Size(360, 740),
        padding: android,
        scale: 1.0,
        accounts: false,
        search: false
      ),
      (
        name: 'fit_412x915',
        size: const Size(412, 915),
        padding: android,
        scale: 1.0,
        accounts: false,
        search: false
      ),
      (
        name: 'scroll_320x568',
        size: const Size(320, 568),
        padding: android,
        scale: 1.0,
        accounts: false,
        search: false
      ),
      (
        name: 'scroll_text_1_6',
        size: const Size(392, 850),
        padding: android,
        scale: 1.6,
        accounts: false,
        search: false
      ),
      (
        name: 'scroll_accounts',
        size: const Size(392, 850),
        padding: android,
        scale: 1.0,
        accounts: true,
        search: false
      ),
    ];
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final screen in screens) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = screen.size;
        tester.view.padding = FakeViewPadding(
            top: screen.padding.top, bottom: screen.padding.bottom);
        addTearDown(tester.view.reset);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final key = GlobalKey();
        final controller = AppThemeController();
        await tester.pumpWidget(previewApp(
          key: key,
          controller: controller,
          mode: mode,
          scale: screen.scale,
          home: login(
              state: AppState((b) => b.loginState.otherAccounts.addAll(
                  screen.accounts ? ['maria.muster', 'max.muster'] : []))),
        ));
        await tester.pumpAndSettle();
        await capturePreview(tester, key, 'fit/${screen.name}_${mode.name}');
        if (screen.search) {
          // The suggestion list opening, then mid-scroll.
          await tester.enterText(field('Schule'), 'Schulsprengel');
          await tester.pump();
          var elapsed = 0;
          for (final at in [0, 60, 160]) {
            await tester.pump(Duration(milliseconds: at - elapsed));
            elapsed = at;
            await capturePreview(
                tester, key, 'fit/suggestions_${at}_${mode.name}');
          }
          await tester.pumpAndSettle();
          final gesture = await tester
              .startGesture(tester.getCenter(find.byType(ListView)));
          for (var step = 0; step < 4; step++) {
            await gesture.moveBy(const Offset(0, -30));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await capturePreview(
              tester, key, 'fit/suggestions_dragging_${mode.name}');
          await gesture.up();
          await tester.pumpAndSettle();
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.enterText(field('Schule'), '');
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
        }
        // A typical keyboard (38 % of the screen) everywhere, plus a tall one
        // (50 %) on the small phone, where the header has to fold away.
        for (final ratio in screen.name == 'fit_360x740'
            ? const [0.38, 0.5]
            : screen.name.startsWith('fit_')
                ? const [0.38]
                : const <double>[]) {
          // The navigation bar's padding drops to zero while the keyboard
          // covers it.
          final height = (screen.size.height * ratio).roundToDouble();
          Future<void> keyboard(double from, double to) async {
            tester.view.padding = FakeViewPadding(
                top: screen.padding.top,
                bottom: to > 0 ? 0 : screen.padding.bottom);
            for (var step = 1; step <= 6; step++) {
              tester.view.viewInsets =
                  FakeViewPadding(bottom: from + (to - from) * step / 6);
              await tester.pump(const Duration(milliseconds: 40));
            }
            await tester.pump(const Duration(milliseconds: 100));
            await tester.pumpAndSettle();
          }

          await tester.tap(field('Schule'));
          await tester.pump();
          await keyboard(0, height);
          final name = screen.name.replaceFirst('fit_', 'keyboard_') +
              (ratio == 0.5 ? '_tall' : '');
          await capturePreview(tester, key, 'fit/${name}_focused_${mode.name}');
          for (final (label, query) in [
            ('few', 'Fallmerayer'),
            ('many', 'Schulsprengel'),
          ]) {
            await tester.enterText(field('Schule'), query);
            await tester.pumpAndSettle();
            await capturePreview(
                tester, key, 'fit/${name}_${label}_${mode.name}');
          }
          if (screen.search && ratio == 0.38) {
            // Next: focus hands over to the username field while the
            // keyboard stays up, and the header comes back.
            await tester.testTextInput.receiveAction(TextInputAction.next);
            await tester.pump();
            var elapsed = 0;
            for (final at in [0, 60, 120, 260]) {
              await tester.pump(Duration(milliseconds: at - elapsed));
              elapsed = at;
              await capturePreview(
                  tester, key, 'fit/handoff_${at}_${mode.name}');
            }
          } else {
            FocusManager.instance.primaryFocus!.nextFocus();
          }
          await tester.pumpAndSettle();
          await capturePreview(
              tester, key, 'fit/${name}_restored_${mode.name}');
          await keyboard(height, 0);
          tester.view.resetViewInsets();
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    }
    debugDisableShadows = previousShadows;
  });
}

Future<void> loadPreviewFonts(WidgetTester tester) => tester.runAsync(() async {
      Future<void> load(String family, Iterable<String> files) async {
        final loader = FontLoader(family);
        for (final file in files.where((f) => File(f).existsSync())) {
          loader.addFont(Future.value(
              ByteData.sublistView(await File(file).readAsBytes())));
        }
        await loader.load();
      }

      final flutterRoot = Platform.environment['FLUTTER_ROOT'];
      if (flutterRoot != null) {
        final root = '$flutterRoot/bin/cache/artifacts/material_fonts';
        final roboto = [
          for (final weight in ['regular', 'medium', 'bold'])
            '$root/roboto-$weight.ttf'
        ];
        await load('Roboto', roboto);
        // No SF fonts here; the iOS preview checks layout and controls only.
        await load('CupertinoSystemText', roboto);
        await load('CupertinoSystemDisplay', roboto);
        await load('MaterialIcons', ['$root/materialicons-regular.otf']);
      }
      const windowsFonts = 'C:/Windows/Fonts';
      await load('Segoe UI', [
        for (final file in ['segoeuil', 'segoeui', 'seguisb', 'segoeuib'])
          '$windowsFonts/$file.ttf'
      ]);
    });

/// The app's real themes around [home], inside a boundary for screenshots.
Widget previewApp({
  required GlobalKey key,
  required AppThemeController controller,
  required ThemeMode mode,
  required Widget home,
  double scale = 1,
}) =>
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        theme: controller.buildTheme(
            brightness: Brightness.light, amoledMode: false),
        darkTheme: controller.buildTheme(
            brightness: Brightness.dark, amoledMode: false),
        themeMode: mode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    );

Future<void> capturePreview(WidgetTester tester, GlobalKey key, String name) =>
    tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rendered = await boundary.toImage();
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/auth_previews/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      rendered.dispose();
    });
