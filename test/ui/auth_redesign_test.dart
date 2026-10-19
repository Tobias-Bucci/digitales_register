import 'dart:io';
import 'dart:ui' as ui;

import 'package:dr/app_state.dart';
import 'package:dr/config.dart';
import 'package:dr/container/login_page.dart' show LoginPageViewModel;
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/auth_layout.dart';
import 'package:dr/ui/login_page_content.dart';
import 'package:dr/ui/pass_reset.dart';
import 'package:dr/ui/request_pass_reset.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
    await tester.enterText(
        field('Adresse'), 'https://example.digitalesregister.it');
    await tester.enterText(field('Benutzername'), 'student');
    await tester.enterText(field('Passwort'), '  Exact password!  ');
    await revealAndTap(tester, find.byType(SwitchListTile));
    final selected =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value;
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

  testWidgets('empty credentials still reach existing middleware validation',
      (tester) async {
    List<String>? payload;
    await pumpApp(tester,
        store: createStore(),
        home: login(
          onLogin: (user, pass, url) => payload = [user, pass, url],
        ));
    await revealAndTap(tester, find.widgetWithText(ElevatedButton, 'Anmelden'));
    expect(payload?.take(2), ['', '']);
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
    expect(tester.widget<TextField>(field('Adresse')).controller!.text,
        school.value);
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
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Bitte warten …'), findsOneWidget);
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
    final semantics = tester.ensureSemantics();
    final messageSemantics = tester.getSemantics(find
        .descendant(
            of: find.byType(AuthMessage), matching: find.byType(Semantics))
        .first);
    expect(messageSemantics.getSemanticsData().flagsCollection.isLiveRegion,
        isTrue);
    semantics.dispose();
    await revealAndTap(tester, find.widgetWithText(ElevatedButton, 'Anmelden'));
    expect(submissions, 1);
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
    await tester.runAsync(() async {
      final flutterRoot = Platform.environment['FLUTTER_ROOT'];
      if (flutterRoot != null) {
        final root = '$flutterRoot/bin/cache/artifacts/material_fonts';
        final loader = FontLoader('Roboto');
        for (final font in [
          'roboto-regular.ttf',
          'roboto-medium.ttf',
          'roboto-bold.ttf'
        ]) {
          loader.addFont(Future.value(
              ByteData.sublistView(await File('$root/$font').readAsBytes())));
        }
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(
              await File('$root/materialicons-regular.otf').readAsBytes())));
        await icons.load();
      }
    });
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final page in [
        'login',
        'accounts',
        'error',
        'loading',
        'change',
        'request',
        'reset',
        'success',
        'desktop',
        'tablet_portrait',
        'tablet_landscape',
      ]) {
        final size = switch (page) {
          'desktop' => const Size(1440, 1000),
          'tablet_portrait' => const Size(768, 1024),
          'tablet_landscape' => const Size(1024, 768),
          _ => const Size(390, 844),
        };
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final state = AppState((b) => b
          ..loginState.changePassword = (page == 'change')
          ..loginState.mustChangePassword = (page == 'change')
          ..loginState.loading = (page == 'loading')
          ..loginState.errorMsg =
              (page == 'error' ? 'Ungültiger Benutzer/Passwort' : null)
          ..loginState.otherAccounts.addAll(page == 'accounts'
              ? ['maria.muster', 'max.muster']
              : <String>[]));
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
        await tester.pumpWidget(RepaintBoundary(
            key: boundaryKey,
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
              theme: ThemeData(colorSchemeSeed: const Color(0xFF3D79AF)),
              darkTheme: ThemeData(
                  colorSchemeSeed: const Color(0xFF3D79AF),
                  brightness: Brightness.dark),
              themeMode: mode,
              home: home,
            )));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.runAsync(() => precacheImage(
            const AssetImage('assets/Icon-App-512x512.png'),
            tester.element(find.byType(AuthLayout))));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.runAsync(() async {
          final boundary = boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final rendered = await boundary.toImage();
          final bytes =
              await rendered.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/auth_previews/${page}_${mode.name}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          rendered.dispose();
        });
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox());
    debugDisableShadows = previousShadows;
  });
}
