import 'package:dr/ui/about_app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'privacy_ui_test.dart' show app;

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(1024, 768)
  ]) {
    for (final brightness in Brightness.values) {
      for (final locale in [
        const Locale('de'),
        const Locale('it'),
        const Locale('en'),
        const Locale('de', 'LLD')
      ]) {
        testWidgets(
            'about layout ${size.width} ${brightness.name} ${locale.toLanguageTag()}',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(app(
              Builder(
                  builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) =>
                                  const AboutAppDialog(version: '1.17.0')),
                          child: const Text('open')))),
              brightness: brightness,
              locale: locale));
          await tester.pumpAndSettle();
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(find.text('v1.17.0'), findsOneWidget);
          expect(find.text('digitalesregister.it'), findsOneWidget);
          expect(find.text('GNU GPLv3'), findsNothing);
          expect(
              tester.getSize(find.byKey(const Key('about-dialog-panel'))).width,
              lessThanOrEqualTo(440));
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byType(ExpansionTile));
          await tester.tap(find.byType(ExpansionTile));
          await tester.pumpAndSettle();
          expect(find.text('GNU GPLv3'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
          await tester.pumpAndSettle();
          expect(find.byType(AboutAppDialog), findsNothing);
        });
      }
    }
  }
}
