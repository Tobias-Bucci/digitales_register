import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

Widget _scaffold() => MaterialApp(
      home: ResponsiveScaffold<String>(
        navKey: GlobalKey<NavigatorState>(),
        homeId: 'home',
        homeBody: const Text('Dashboard'),
        homeAppBar: AppBar(title: const Text('Register')),
        drawerBuilder: (select, home, selected, tablet) =>
            const SizedBox(width: 68, child: Material()),
      ),
    );

void main() {
  testWidgets(
      'removing the scaffold during a resize animation releases its ticker',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (var round = 0; round < 3; round++) {
      tester.view.physicalSize = const Size(800, 600);
      await tester.pumpWidget(_scaffold());
      await tester.pump();
      expect(find.text('Dashboard'), findsOneWidget);

      // Leaving tablet mode starts the 250 ms drawer animation; remove the
      // scaffold while it is still running.
      tester.view.physicalSize = const Size(600, 600);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull, reason: 'round $round');
    }
  });
}
