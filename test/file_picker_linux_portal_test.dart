import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

// The vendored file_picker package brings dbus; the app does not use it.
// ignore: depend_on_referenced_packages
import 'package:dbus/dbus.dart';
import 'package:file_picker/src/api/file_picker_types.dart';
import 'package:file_picker/src/platform/linux/file_picker_linux.dart';
import 'package:file_picker/src/platform/linux/xdp_portal_connection.dart';
import 'package:flutter_test/flutter_test.dart';

/// Decides how the fake portal answers OpenFile/SaveFile. It returns the
/// handle carried by the method reply and may emit responses before or after.
typedef _PortalCall = Future<DBusObjectPath> Function(
    _FakePortal portal, String method, Map<String, DBusValue> options);

/// Fake session bus connection with a portal behind it. Like a real bus, a
/// response emitted while nobody listens on its handle is lost.
class _FakePortal implements XdpPortalConnection {
  _FakePortal(this.onCall);

  final _PortalCall onCall;
  final calls = <(String, String, Map<String, DBusValue>)>[];
  final closedRequests = <DBusObjectPath>[];
  final _listeners = <DBusObjectPath, List<StreamController<XdpResponse>>>{};
  bool closed = false;
  int lostResponses = 0;

  /// The handle a current portal derives from sender and handle_token.
  DBusObjectPath requestHandle(Map<String, DBusValue> options) =>
      DBusObjectPath('/org/freedesktop/portal/desktop/request/1_42/'
          '${options['handle_token']!.asString()}');

  void emit(DBusObjectPath handle, XdpResponse response) {
    final listeners = _listeners[handle] ?? [];
    if (listeners.isEmpty) lostResponses++;
    for (final listener in listeners) {
      listener.add(response);
    }
  }

  int get activeListeners =>
      _listeners.values.fold(0, (sum, list) => sum + list.length);

  @override
  Future<String> connect() async => ':1.42';

  @override
  Future<StreamSubscription<XdpResponse>> listenForResponse(
    DBusObjectPath handle,
    void Function(XdpResponse response) onResponse,
    void Function(Object error, StackTrace stackTrace) onError,
  ) async {
    late final StreamController<XdpResponse> controller;
    controller = StreamController<XdpResponse>(
        onCancel: () => _listeners[handle]!.remove(controller));
    _listeners.putIfAbsent(handle, () => []).add(controller);
    return controller.stream.listen(onResponse, onError: onError);
  }

  @override
  Future<DBusObjectPath> callOpenFile(
      String parentWindow, String title, Map<String, DBusValue> options) {
    calls.add(('OpenFile', title, options));
    return onCall(this, 'OpenFile', options);
  }

  @override
  Future<DBusObjectPath> callSaveFile(
      String parentWindow, String title, Map<String, DBusValue> options) {
    calls.add(('SaveFile', title, options));
    return onCall(this, 'SaveFile', options);
  }

  @override
  Future<void> closeRequest(DBusObjectPath handle) async =>
      closedRequests.add(handle);

  @override
  Future<void> close() async => closed = true;
}

XdpResponse _selected(List<String> uris) =>
    XdpResponse(0, {'uris': DBusArray.string(uris)});

const _cancelled = XdpResponse(1, {});

/// Answers after the method reply, like an interactive dialog.
_PortalCall _answerLater(XdpResponse response, {DBusObjectPath? legacy}) =>
    (portal, method, options) async {
      final handle = legacy ?? portal.requestHandle(options);
      Timer(const Duration(milliseconds: 10),
          () => portal.emit(handle, response));
      return handle;
    };

final _legacyHandle =
    DBusObjectPath('/org/freedesktop/portal/desktop/request/legacy/7');

void main() {
  late Directory dir;
  late List<_FakePortal> portals;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('linux_picker_test');
    portals = [];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  FilePickerLinux picker(_PortalCall onCall,
          {Duration timeout = const Duration(seconds: 2)}) =>
      FilePickerLinux(
        responseTimeout: timeout,
        connectionFactory: () {
          final portal = _FakePortal(onCall);
          portals.add(portal);
          return portal;
        },
      );

  String file(String name, [int length = 3]) {
    final created = File('${dir.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(List.filled(length, 1));
    return created.path;
  }

  void expectReleased(_FakePortal portal) {
    expect(portal.activeListeners, 0, reason: 'subscriptions cancelled');
    expect(portal.closed, isTrue, reason: 'connection closed');
  }

  group('response ordering', () {
    test('a response emitted before the method reply is delivered', () async {
      final path = file('early.txt');
      final result = await picker((portal, method, options) async {
        final handle = portal.requestHandle(options);
        portal.emit(handle, _selected([Uri.file(path).toString()]));
        await Future<void>.delayed(Duration.zero);
        return handle;
      }).pickFiles();

      expect(result?.paths, [path]);
      expect(portals.single.lostResponses, 0);
      expect(portals.single.closedRequests, isEmpty);
      expectReleased(portals.single);
    });

    test('a response emitted after the method reply is delivered', () async {
      final path = file('late.txt');
      final result =
          await picker(_answerLater(_selected([Uri.file(path).toString()])))
              .pickFiles();

      expect(result?.paths, [path]);
      expect(portals.single.closedRequests, isEmpty);
      expectReleased(portals.single);
    });

    test('a different returned handle is followed', () async {
      final path = file('legacy.txt');
      final result = await picker(_answerLater(
              _selected([Uri.file(path).toString()]),
              legacy: _legacyHandle))
          .pickFiles();

      expect(result?.paths, [path]);
      expect(portals.single.closedRequests, isEmpty);
      expectReleased(portals.single);
    });

    test('a response on the expected handle is kept when the reply differs',
        () async {
      final path = file('kept.txt');
      final result = await picker((portal, method, options) async {
        portal.emit(portal.requestHandle(options),
            _selected([Uri.file(path).toString()]));
        await Future<void>.delayed(Duration.zero);
        return _legacyHandle;
      }).pickFiles();

      expect(result?.paths, [path]);
      expectReleased(portals.single);
    });
  });

  group('cancellation and timeout', () {
    test('cancelling in the dialog returns null without Close', () async {
      expect(await picker(_answerLater(_cancelled)).pickFiles(), isNull);
      expect(portals.single.closedRequests, isEmpty);
      expectReleased(portals.single);
    });

    test('a missing response times out, closes the request and cleans up',
        () async {
      late DBusObjectPath handle;
      final result = await picker((portal, method, options) async {
        return handle = portal.requestHandle(options);
      }, timeout: const Duration(milliseconds: 50))
          .pickFiles();

      expect(result, isNull);
      expect(portals.single.closedRequests, [handle]);
      expectReleased(portals.single);
    });

    test('a timeout closes the returned legacy handle', () async {
      final result = await picker((portal, method, options) async {
        return _legacyHandle;
      }, timeout: const Duration(milliseconds: 50))
          .saveFile(fileName: 'a.txt');

      expect(result, isNull);
      expect(portals.single.closedRequests, [_legacyHandle]);
      expectReleased(portals.single);
    });

    test('a hanging method call times out as well', () async {
      final never = Completer<DBusObjectPath>();
      final result = await picker((portal, method, options) => never.future,
              timeout: const Duration(milliseconds: 50))
          .getDirectoryPath();

      expect(result, isNull);
      expect(portals.single.closedRequests, hasLength(1));
      expectReleased(portals.single);
    });

    test('a failing method call is reported and cleans up', () async {
      await expectLater(
        picker((portal, method, options) async => throw StateError('portal'))
            .pickFiles(),
        throwsStateError,
      );
      expect(portals.single.closedRequests, isEmpty);
      expectReleased(portals.single);
    });
  });

  group('normal behaviour', () {
    test('pickFiles sends the options and returns the selected file', () async {
      final path = file('single.txt', 5);
      final result =
          await picker(_answerLater(_selected([Uri.file(path).toString()])))
              .pickFiles(
                  dialogTitle: 'Choose',
                  type: FileType.custom,
                  allowedExtensions: ['txt']);

      final (method, title, options) = portals.single.calls.single;
      expect(method, 'OpenFile');
      expect(title, 'Choose');
      expect(options['multiple'], const DBusBoolean(false));
      expect(options['filters']!.asArray(), isNotEmpty);
      expect(options['handle_token']!.asString(), startsWith('flutter_picker'));
      expect(result!.files.single.name, 'single.txt');
      expect(result.files.single.size, 5);
    });

    test('pickFiles returns several files', () async {
      final first = file('one.txt');
      final second = file('two.txt');
      final result = await picker(_answerLater(_selected(
              [Uri.file(first).toString(), Uri.file(second).toString()])))
          .pickFiles(allowMultiple: true);

      expect(
          portals.single.calls.single.$3['multiple'], const DBusBoolean(true));
      expect(result?.paths, [first, second]);
    });

    test('getDirectoryPath returns the chosen directory', () async {
      final result = await picker(
              _answerLater(_selected([Uri.directory(dir.path).toString()])))
          .getDirectoryPath();

      expect(
          portals.single.calls.single.$3['directory'], const DBusBoolean(true));
      expect(Directory(result!).absolute.path,
          startsWith(Directory(dir.path).absolute.path));
      expectReleased(portals.single);
    });

    test('saveFile writes the bytes to the chosen path', () async {
      final target = '${dir.path}${Platform.pathSeparator}saved.txt';
      final result =
          await picker(_answerLater(_selected([Uri.file(target).toString()])))
              .saveFile(
                  fileName: 'saved.txt', bytes: Uint8List.fromList([7, 8]));

      final (method, _, options) = portals.single.calls.single;
      expect(method, 'SaveFile');
      expect(options['current_name'], const DBusString('saved.txt'));
      expect(result, target);
      expect(File(target).readAsBytesSync(), [7, 8]);
      expectReleased(portals.single);
    });

    test('directory and save dialogs return null when cancelled', () async {
      expect(await picker(_answerLater(_cancelled)).getDirectoryPath(), isNull);
      expect(await picker(_answerLater(_cancelled)).saveFile(), isNull);
      portals.forEach(expectReleased);
    });

    test('each dialog uses its own connection and handle token', () async {
      final path = file('again.txt');
      final linux =
          picker(_answerLater(_selected([Uri.file(path).toString()])));
      await linux.pickFiles();
      await linux.pickFiles();

      expect(portals, hasLength(2));
      expect(portals[0].calls.single.$3['handle_token'],
          isNot(portals[1].calls.single.$3['handle_token']));
      portals.forEach(expectReleased);
    });
  });
}
