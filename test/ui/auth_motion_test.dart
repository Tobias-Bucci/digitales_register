import 'package:dr/app_state.dart';
import 'package:dr/container/login_page.dart' show LoginPageViewModel;
import 'package:dr/theme/auth_tokens.dart';
import 'package:dr/ui/auth_layout.dart';
import 'package:dr/ui/login_page_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

/// The login screen driven by a changing app state, so the same screen
/// instance sees loading, errors and recovery like in the app.
Widget host(ValueNotifier<AppState> state,
        {LoginCallback? onLogin, bool reducedMotion = false}) =>
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: ValueListenableBuilder<AppState>(
          valueListenable: state,
          builder: (context, value, _) => LoginPageContent(
            vm: LoginPageViewModel.from(value),
            onLogin: onLogin ?? (_, __, ___) {},
            onChangePass: (_, __, ___, ____) {},
            setSaveNoPass: (_) {},
            onReload: () {},
            onRequestPassReset: (_) {},
            onSelectAccount: (_) {},
            onRemoveAccount: (_) {},
          ),
        ),
      ),
    );

Iterable<double> entranceOpacities(WidgetTester tester) => tester
    .widgetList<FadeTransition>(find.descendant(
        of: find.byType(AuthLayout), matching: find.byType(FadeTransition)))
    .map((fade) => fade.opacity.value);

Color buttonFill(WidgetTester tester) => tester
    .widget<ElevatedButton>(find.byType(ElevatedButton))
    .style!
    .backgroundColor!
    .resolve(const {})!;

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  testWidgets('entrance assembles top to bottom and stays interactive',
      (tester) async {
    await tester.pumpWidget(buildTestApp(
        store: createStore(), home: host(ValueNotifier(AppState()))));
    await tester.pump(); // the ticker's first frame has no elapsed time
    await tester.pump(const Duration(milliseconds: 100));
    double opacityAbove(Finder finder) => tester
        // Entrance fades keep their content in the semantics tree; the
        // outermost (listed last) is the entrance; the icon also has a
        // fold-away.
        .widget<FadeTransition>(find
            .ancestor(
                of: finder,
                matching: find.byWidgetPredicate((widget) =>
                    widget is FadeTransition && widget.alwaysIncludeSemantics))
            .last)
        .opacity
        .value;
    final icon = opacityAbove(find.byType(AuthAppIcon));
    final footer = opacityAbove(find.text('Feedback senden'));
    // The icon leads; the footer has not started yet.
    expect(icon, greaterThan(0));
    expect(icon, lessThan(1));
    expect(footer, lessThan(icon));

    // Input is never blocked while the screen assembles.
    await tester.tap(field('Benutzername'), warnIfMissed: false);
    await tester.pump();
    expect(
        tester
            .widget<EditableText>(find.descendant(
                of: field('Benutzername'), matching: find.byType(EditableText)))
            .focusNode
            .hasFocus,
        isTrue);

    await tester.pumpAndSettle();
    expect(entranceOpacities(tester).every((opacity) => opacity == 1), isTrue);
    final settled = tester.getTopLeft(field('Passwort'));
    // A rebuild (e.g. typing) never replays the entrance.
    await tester.enterText(field('Benutzername'), 'student');
    await tester.pump(const Duration(milliseconds: 16));
    expect(entranceOpacities(tester).every((opacity) => opacity == 1), isTrue);
    expect(tester.getTopLeft(field('Passwort')), settled);
  });

  testWidgets('the button wakes up with a cross-fade once fields are valid',
      (tester) async {
    await tester.pumpWidget(buildTestApp(
        store: createStore(), home: host(ValueNotifier(AppState()))));
    await tester.pumpAndSettle();
    final tokens = AuthTokens.of(tester.element(find.byType(ElevatedButton)));
    expect(buttonFill(tester), tokens.disabledFill);
    await tester.enterText(field('Benutzername'), 'student');
    await tester.enterText(field('Passwort'), 'secret');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final mid = buttonFill(tester);
    expect(mid, isNot(tokens.disabledFill));
    expect(mid, isNot(tokens.accentFill));
    await tester.pumpAndSettle();
    expect(buttonFill(tester), tokens.accentFill);
  });

  testWidgets('loading swaps label for spinner at a constant size',
      (tester) async {
    final state = ValueNotifier(AppState());
    await tester
        .pumpWidget(buildTestApp(store: createStore(), home: host(state)));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(ElevatedButton));
    state.value = AppState((b) => b.loginState.loading = true);
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.getSize(find.byType(ElevatedButton)), size);
    }
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Anmelden'), findsNothing);
    state.value = AppState();
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ElevatedButton)), size);
    expect(find.text('Anmelden'), findsOneWidget);
  });

  testWidgets('error message grows in, then collapses when cleared',
      (tester) async {
    final state = ValueNotifier(AppState());
    await tester
        .pumpWidget(buildTestApp(store: createStore(), home: host(state)));
    await tester.pumpAndSettle();
    final buttonTop = tester.getTopLeft(find.byType(ElevatedButton)).dy;
    state.value =
        AppState((b) => b.loginState.errorMsg = 'Ungültiger Benutzer/Passwort');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final midTop = tester.getTopLeft(find.byType(ElevatedButton)).dy;
    await tester.pumpAndSettle();
    final finalTop = tester.getTopLeft(find.byType(ElevatedButton)).dy;
    // The button glides down instead of jumping.
    expect(midTop, greaterThan(buttonTop));
    expect(midTop, lessThan(finalTop));
    expect(find.byType(AuthMessage), findsOneWidget);

    state.value = AppState();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(AuthMessage), findsOneWidget); // still folding away
    await tester.pumpAndSettle();
    expect(find.byType(AuthMessage), findsNothing);
    expect(tester.getTopLeft(find.byType(ElevatedButton)).dy, buttonTop);
  });

  Future<List<double>> sampleShake(WidgetTester tester, double restX) async {
    final offsets = <double>[];
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      offsets.add(tester.getTopLeft(field('Benutzername')).dx - restX);
    }
    await tester.pumpAndSettle();
    return offsets;
  }

  testWidgets('the form shakes once per rejected sign-in attempt',
      (tester) async {
    final state = ValueNotifier(AppState());
    await tester
        .pumpWidget(buildTestApp(store: createStore(), home: host(state)));
    await tester.pumpAndSettle();
    final restX = tester.getTopLeft(field('Benutzername')).dx;
    AppState loading() => AppState((b) => b.loginState.loading = true);
    AppState rejected() =>
        AppState((b) => b.loginState.errorMsg = 'Ungültiger Benutzer/Passwort');

    state.value = loading();
    await tester.pump(const Duration(milliseconds: 300));
    state.value = rejected();
    final first = await sampleShake(tester, restX);
    expect(first.map((dx) => dx.abs()).reduce((a, b) => a > b ? a : b),
        inInclusiveRange(3, 6));
    expect(tester.getTopLeft(field('Benutzername')).dx, restX);

    // Rebuilding with the same error is not a new attempt.
    state.value = rejected();
    final rebuild = await sampleShake(tester, restX);
    expect(rebuild.every((dx) => dx == 0), isTrue);

    // A second failed attempt shakes again.
    state.value = loading();
    await tester.pump(const Duration(milliseconds: 300));
    state.value = rejected();
    final second = await sampleShake(tester, restX);
    expect(second.any((dx) => dx.abs() > 3), isTrue);
  });

  testWidgets('connection errors and untouched fields never shake',
      (tester) async {
    final state = ValueNotifier(AppState());
    await tester
        .pumpWidget(buildTestApp(store: createStore(), home: host(state)));
    await tester.pumpAndSettle();
    final restX = tester.getTopLeft(field('Benutzername')).dx;
    state.value = AppState((b) => b.loginState.loading = true);
    await tester.pump(const Duration(milliseconds: 300));
    state.value = AppState((b) => b
      ..noInternet = true
      ..loginState.errorMsg = 'network');
    final offsets = await sampleShake(tester, restX);
    expect(offsets.every((dx) => dx == 0), isTrue);
  });

  testWidgets('reduced motion starts settled and never moves the form',
      (tester) async {
    final state = ValueNotifier(AppState());
    await tester.pumpWidget(buildTestApp(
        store: createStore(), home: host(state, reducedMotion: true)));
    await tester.pump();
    expect(entranceOpacities(tester).every((opacity) => opacity == 1), isTrue);
    final restTopLeft = tester.getTopLeft(field('Benutzername'));
    final buttonSize = tester.getSize(find.byType(ElevatedButton));

    state.value = AppState((b) => b.loginState.loading = true);
    await tester.pump(const Duration(milliseconds: 300));
    state.value =
        AppState((b) => b.loginState.errorMsg = 'Ungültiger Benutzer/Passwort');
    final offsets = await sampleShake(tester, restTopLeft.dx);
    expect(offsets.every((dx) => dx == 0), isTrue);
    expect(find.byType(AuthMessage), findsOneWidget);
    expect(tester.getTopLeft(field('Benutzername')), restTopLeft);
    expect(tester.getSize(find.byType(ElevatedButton)), buttonSize);
    expect(tester.takeException(), isNull);
  });

  testWidgets('address reveal fits 320x640 at 1.6x text in every frame',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildTestApp(
      store: createStore(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: host(ValueNotifier(AppState())),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(field('Schule'), 'Unbekannte Schule');
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pumpAndSettle();
    final link = find.text('Adresse manuell eingeben');
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    await tester.tap(link);
    // 0 %, ~30 %, ~60 % and 100 % of the 260 ms reveal.
    for (final step in [0, 80, 80, 200]) {
      await tester.pump(Duration(milliseconds: step));
      expect(tester.takeException(), isNull);
    }
    expect(field('Adresse'), findsOneWidget);
    expect(tester.getRect(field('Adresse')).right, lessThanOrEqualTo(320));
  });
}
