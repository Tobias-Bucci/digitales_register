import 'package:dr/external_links.dart';
import 'package:dr/ui/welcome_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

// #145: the links of the welcome dialog open through the shared link check
// (#141), look like the other links of the app and do not leak their tap
// recognizers.

const _oldProject = 'https://github.com/miDeb/digitales_register';
const _newProject = 'https://github.com/Tobias-Bucci/digitales_register';

/// The links the dialog shows, in order.
List<TextSpan> _links(WidgetTester tester) {
  final links = <TextSpan>[];
  final dialog = find.byType(WelcomeDialog);
  for (final rich in tester.widgetList<RichText>(
      find.descendant(of: dialog, matching: find.byType(RichText)))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null) links.add(span);
      return true;
    });
  }
  return links;
}

void main() {
  late List<Uri> launched;
  var launches = true;

  setUp(() async {
    await bootstrapTestEnvironment();
    launched = [];
    launches = true;
    externalLinkLauncherOverride = (uri) async {
      launched.add(uri);
      return launches;
    };
  });
  tearDown(() async {
    externalLinkLauncherOverride = null;
    await resetTestState();
  });

  Future<void> open(
    WidgetTester tester, {
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    await pumpApp(
      tester,
      store: createStore(),
      themeMode: themeMode,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWelcomeDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeDialog), findsOneWidget);
  }

  testWidgets('shows both project links', (tester) async {
    await open(tester);

    expect(_links(tester).map((span) => span.text), [
      'github.com/mideb/digitales_register',
      'github.com/Tobias-Bucci/digitales_register',
    ]);
  });

  testWidgets('a tap opens the link through the shared check', (tester) async {
    await open(tester);

    for (final link in _links(tester)) {
      (link.recognizer! as TapGestureRecognizer).onTap!();
      await tester.pump();
    }

    expect(launched, [Uri.parse(_oldProject), Uri.parse(_newProject)]);
    expect(find.text('Dieser Link konnte nicht geöffnet werden'), findsNothing);
  });

  testWidgets('a failed launch shows the failure message', (tester) async {
    launches = false;
    await open(tester);

    (_links(tester).last.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();
    await tester.pump();

    expect(launched, [Uri.parse(_newProject)]);
    expect(
        find.text('Dieser Link konnte nicht geöffnet werden'), findsOneWidget);
  });

  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('the links use the theme color and an underline ($themeMode)',
        (tester) async {
      await open(tester, themeMode: themeMode);

      final context = tester.element(find.byType(WelcomeDialog));
      expect(Theme.of(context).brightness,
          themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light);
      final primary = Theme.of(context).colorScheme.primary;
      for (final link in _links(tester)) {
        expect(link.style?.color, primary, reason: link.text);
        expect(
            link.style?.decoration?.contains(TextDecoration.underline), isTrue,
            reason: link.text);
      }
    });
  }

  testWidgets('the tap recognizers are disposed when the dialog closes',
      (tester) async {
    final created = <Object>{};
    final disposed = <Object>{};
    void track(ObjectEvent event) {
      if (event.object is! TapGestureRecognizer) return;
      if (event is ObjectCreated) created.add(event.object);
      if (event is ObjectDisposed) disposed.add(event.object);
    }

    FlutterMemoryAllocations.instance.addListener(track);
    addTearDown(() => FlutterMemoryAllocations.instance.removeListener(track));

    await open(tester);
    // A rebuild, as when the text size changes, makes no new recognizers.
    final before = _links(tester).map((span) => span.recognizer).toList();
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(_links(tester).map((span) => span.recognizer), before);
    expect(disposed, isEmpty);

    await tester.tap(find.byTooltip('Dialog schließen'));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeDialog), findsNothing);
    // The dialog made exactly its two link recognizers and disposed both;
    // the gesture detectors of the page behind it are not its business.
    expect(before, hasLength(2));
    expect(created, containsAll(before));
    expect(disposed, containsAll(before));
  });
}
