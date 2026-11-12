// The grade chart draws with the vendored charts packages; this guards a
// crash inside them, so it reaches into their implementation.
// ignore_for_file: depend_on_referenced_packages, implementation_imports
import 'package:charts_common/common.dart' show LocalDateTimeFactory;
import 'package:charts_common/src/chart/cartesian/axis/linear/linear_scale.dart';
import 'package:charts_common/src/chart/cartesian/axis/scale.dart';
import 'package:charts_common/src/chart/cartesian/axis/time/date_time_scale.dart';
import 'package:flutter_test/flutter_test.dart';

/// A chart that is laid out with no width (offstage, or while the screen
/// rotates) has a 0 px range. Mapping a pixel back to a date divided by a
/// zero scaling factor and crashed with "Infinity or NaN toInt"
/// (Crashlytics dc34fd7e, #23).
void main() {
  final first = DateTime(2026, 9, 10);
  final last = DateTime(2026, 11, 12);

  test('date scale with a zero-width range maps pixels to the domain start',
      () {
    final scale = DateTimeScale(const LocalDateTimeFactory())
      ..addDomain(first)
      ..addDomain(last)
      ..range = const ScaleOutputExtent(0, 0);
    expect(scale.reverse(0), first);
    expect(scale.reverse(120), first);
  });

  test('linear scale with a zero-width range stays finite', () {
    final scale = LinearScale()
      ..addDomain(3)
      ..addDomain(9)
      ..range = const ScaleOutputExtent(40, 40);
    expect(scale.reverse(40), 3);
    expect(scale.reverse(0).isFinite, isTrue);
  });

  test('a normal range still maps pixels across the domain', () {
    final scale = DateTimeScale(const LocalDateTimeFactory())
      ..addDomain(first)
      ..addDomain(last)
      ..range = const ScaleOutputExtent(0, 100);
    expect(scale.reverse(0), first);
    expect(scale.reverse(100), last);
  });
}
