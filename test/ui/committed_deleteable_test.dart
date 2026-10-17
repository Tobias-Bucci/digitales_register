import 'package:dr/ui/committed_deleteable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final animate in [true, false]) {
    for (final unmount in [true, false]) {
      testWidgets('commit once: animate=$animate, unmount=$unmount',
          (tester) async {
        var commits = 0;
        late Future<void> Function() delete;
        await tester.pumpWidget(MaterialApp(
          home: CommittedDeleteable(
            showEntryAnimation: false,
            showExitAnimation: animate,
            onDeleted: () => commits++,
            builder: (context, callback) {
              delete = callback;
              return const SizedBox(height: 100);
            },
          ),
        ));
        final operation = delete();
        expect(identical(operation, delete()), isTrue);
        await tester.pump();
        if (unmount) {
          await tester.pumpWidget(const SizedBox());
        } else {
          await tester.pumpAndSettle();
        }
        await operation;
        expect(commits, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(commits, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('confirmation after tile teardown still commits once',
      (tester) async {
    var commits = 0;
    late Future<void> Function() delete;
    await tester.pumpWidget(MaterialApp(
      home: CommittedDeleteable(
        onDeleted: () => commits++,
        builder: (context, callback) {
          delete = callback;
          return const SizedBox(height: 100);
        },
      ),
    ));
    await tester.pumpWidget(const SizedBox());
    expect(commits, 0);
    await delete();
    await delete();
    expect(commits, 1);
    expect(tester.takeException(), isNull);
  });
}
