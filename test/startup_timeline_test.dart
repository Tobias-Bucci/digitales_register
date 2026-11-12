import 'package:dr/startup_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records each step and point of the cold start once', () async {
    final lines = <String>[];
    final timeline = StartupTimeline(enabled: true, output: lines.add)..start();
    expect(await timeline.step('p1_a', () async => 7), 7);
    expect(await timeline.step('p1_a', () async => 8), 8);
    timeline
      ..mark('p2_first_frame')
      ..mark('p2_first_frame');

    expect(timeline.marks.map((m) => m.name), ['p1_a', 'p2_first_frame']);
    expect(timeline.marks.first.durationMicros, greaterThanOrEqualTo(0));
    expect(lines, hasLength(2));
    expect(lines.first, startsWith('[startup] p1_a at='));
    expect(lines.first, contains('took='));
    expect(lines.last, isNot(contains('took=')));
  });

  test('records nothing before main() started the clock', () async {
    final lines = <String>[];
    final timeline = StartupTimeline(enabled: true, output: lines.add);
    expect(await timeline.step('p1_a', () async => 1), 1);
    timeline.mark('p2_first_frame');
    expect(timeline.marks, isEmpty);
    expect(lines, isEmpty);
  });

  test('a disabled timeline only runs the steps', () async {
    final lines = <String>[];
    final timeline = StartupTimeline(enabled: false, output: lines.add)
      ..start();
    final body = Future.value(3);
    expect(timeline.step('p1_a', () => body), same(body));
    timeline.mark('p2_first_frame');
    expect(timeline.marks, isEmpty);
    expect(lines, isEmpty);
  });

  test('a failing step is still recorded and its error kept', () async {
    final timeline = StartupTimeline(enabled: true, output: (_) {})..start();
    await expectLater(
        timeline.step<void>('p1_fail', () async => throw StateError('x')),
        throwsStateError);
    expect(timeline.marks.single.name, 'p1_fail');
  });
}
