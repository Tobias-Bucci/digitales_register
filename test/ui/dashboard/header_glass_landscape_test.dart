import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

final _today = UtcDateTime(2026, 10, 20);

AppState _longList() => AppState((b) {
      b.dashboardState.future = true;
      b.dashboardState.allDays = ListBuilder<Day>([
        for (var day = 0; day < 14; day++)
          buildDay(
            date: _today.add(Duration(days: day)),
            homework: [
              for (var entry = 0; entry < 1 + day % 3; entry++)
                buildHomework(
                  id: day * 10 + entry + 1,
                  title: 'Hausaufgabe',
                  label: 'Deutsch',
                  checkable: true,
                ),
            ],
          ),
      ]);
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.url = 'https://franziskanergymnasium.digitalesregister.it';
      b.noInternet = false;
    });

/// The backdrop filters of the frame, in the order they are painted.
List<BackdropFilterLayer> _backdropLayers(WidgetTester tester) {
  final layers = <BackdropFilterLayer>[];
  void visit(Layer layer) {
    if (layer is BackdropFilterLayer) layers.add(layer);
    if (layer is ContainerLayer) {
      for (var child = layer.firstChild;
          child != null;
          child = child.nextSibling) {
        visit(child);
      }
    }
  }

  visit(tester.binding.renderViews.first.debugLayer!);
  return layers;
}

BackdropFilterLayer _layerOf(WidgetTester tester, Key surface) {
  final render = tester.renderObject<RenderBackdropFilter>(find.descendant(
    of: find.byKey(surface),
    matching: find.byType(BackdropFilter),
  ));
  return render.debugLayer! as BackdropFilterLayer;
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment(fixedNow: _today);
  });
  tearDown(resetTestState);

  // A phone in landscape, and a desktop window: both with the rail (#118).
  for (final window in const [Size(915, 412), Size(1280, 800)]) {
    testWidgets(
        'in a $window window the header is glass over the list, '
        'with a backdrop that the rail does not take first', (tester) async {
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = createStore(initialState: _longList(), newDesign: true);
      await pumpApp(tester, store: store, home: DaysContainer());
      await settleFor(tester);

      final list = tester
          .widgetList<ListView>(find.byType(ListView))
          .firstWhere((list) => list.controller != null)
          .controller!;
      list.jumpTo(300);
      await tester.pump();

      const headerKey = Key('dashboard-app-header');
      const railKey = Key('app-navigation-rail');
      expect(find.byKey(railKey), findsOneWidget);

      // The list scrolls beneath a translucent, blurred header.
      final header = tester.getRect(find.byKey(headerKey));
      expect(tester.getRect(find.byType(ListView).first).top,
          lessThan(header.top));
      final glass = tester.widget<GlassSurface>(find.byKey(headerKey));
      expect(glass.blur, isTrue);
      expect(glass.opacity, lessThan(1));

      // Filters of one BackdropGroup reuse the backdrop of the first one that
      // is painted. Were it the rail, which comes before the page, the header
      // would show none of the list (as it did with Impeller).
      final headerLayer = _layerOf(tester, headerKey);
      final railLayer = _layerOf(tester, railKey);
      expect(headerLayer.backdropKey, isNotNull);
      expect(railLayer.backdropKey, headerLayer.backdropKey);
      final grouped = _backdropLayers(tester)
          .where((layer) => layer.backdropKey == headerLayer.backdropKey)
          .toList();
      expect(grouped.first, same(headerLayer));
      expect(grouped.indexOf(railLayer), greaterThan(0));

      // The rail still stands at the start of the window.
      expect(tester.getRect(find.byKey(railKey)).left, lessThan(header.left));
    });
  }
}
