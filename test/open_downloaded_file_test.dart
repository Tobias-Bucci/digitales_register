import 'dart:io';

import 'package:dr/app_state.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_file/open_file.dart';

import 'support/test_harness.dart';

const _failure = 'Material could not be opened.';
const _fileName = 'Prüfung mit Leerzeichen.pdf';

void main() {
  late Directory directory;
  late List<String> openedPaths;

  setUp(() async {
    await bootstrapTestEnvironment();
    directory = Directory.systemTemp.createTempSync('open-file-');
    File('${directory.path}/$_fileName').writeAsBytesSync([37, 80, 68, 70]);
    attachmentDownloadDirectoryOverride = () async => directory.path;
    openedPaths = [];
  });

  tearDown(() async {
    attachmentDownloadDirectoryOverride = null;
    downloadedFileOpenerOverride = null;
    directory.deleteSync(recursive: true);
    await resetTestState();
  });

  Future<void> open(WidgetTester tester, Future<OpenResult> Function() result,
      {String fileName = _fileName}) async {
    downloadedFileOpenerOverride = (path) {
      openedPaths.add(path);
      return result();
    };
    await pumpApp(tester,
        store: createStore(
            initialState: AppState((b) => b.settingsState.languageCode = 'en')),
        home: const Scaffold(body: SizedBox()));
    await tester.runAsync(() => openFile(fileName));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
  }

  testWidgets('a successful open shows no error', (tester) async {
    await open(
        tester, () async => OpenResult(type: ResultType.done, message: 'done'));
    expect(openedPaths, ['${directory.path}/$_fileName']);
    expect(find.text(_failure), findsNothing);
  });

  for (final type in [
    ResultType.noAppToOpen,
    ResultType.error,
    ResultType.permissionDenied,
    ResultType.fileNotFound,
  ]) {
    testWidgets('${type.name} shows the open failure', (tester) async {
      await open(tester, () async => OpenResult(type: type, message: 'x'));
      expect(openedPaths, hasLength(1));
      expect(find.text(_failure), findsOneWidget);
    });
  }

  testWidgets('an exception from the plugin shows the open failure',
      (tester) async {
    await open(tester, () => Future.error(StateError('plugin failed')));
    expect(openedPaths, hasLength(1));
    expect(find.text(_failure), findsOneWidget);
  });

  testWidgets('an unsafe file name is not opened and shows the failure',
      (tester) async {
    await open(
        tester, () async => OpenResult(type: ResultType.done, message: 'done'),
        fileName: '../$_fileName');
    expect(openedPaths, isEmpty);
    expect(find.text(_failure), findsOneWidget);
  });
}
