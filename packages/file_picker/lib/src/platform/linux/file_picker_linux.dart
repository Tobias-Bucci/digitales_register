import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/src/api/file_picker_types.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:file_picker/src/api/file_picker_result.dart';
import 'package:file_picker/src/api/platform_file.dart';
import 'package:file_picker/src/file_picker_utils.dart';
import 'package:file_picker/src/platform/linux/xdp_portal_connection.dart';
import 'package:file_picker/src/platform/linux/filters.dart';
import 'package:dbus/dbus.dart';

class FilePickerLinux extends FilePickerPlatform {
  static void registerWith() {
    FilePickerPlatform.instance = FilePickerLinux();
  }

  /// Upper bound for one dialog. Afterwards the dialog is closed and the
  /// request ends as if it had been cancelled.
  static const defaultResponseTimeout = Duration(minutes: 30);

  /// Bound for each cleanup step, so a broken bus cannot block the result.
  static const _cleanupTimeout = Duration(seconds: 5);

  static int _nextToken = 0;

  /// Opens a new connection for each dialog. Defaults to the session bus.
  final XdpPortalConnection Function() _connectionFactory;
  final Duration responseTimeout;

  FilePickerLinux({
    XdpPortalConnection Function()? connectionFactory,
    this.responseTimeout = defaultResponseTimeout,
  })  : _connectionFactory = connectionFactory ??
            (() => DBusXdpPortalConnection(DBusClient.session())),
        super();

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    int compressionQuality = 0,
    bool cancelUploadOnWindowBlur = true,
  }) async {
    final filter = Filter(type, allowedExtensions);
    Map<String, DBusValue> xdpOption = {
      'multiple': DBusBoolean(allowMultiple),
      'modal': DBusBoolean(lockParentWindow),
      'filters': filter.toDBusArray(),
    };
    if (initialDirectory != null) {
      final Uint8List tmp = _encodeDirectory(initialDirectory);
      DBusArray directory = DBusArray.byte(tmp);
      xdpOption["current_folder"] = directory;
    }
    final response = await _request(
        xdpOption,
        (connection, options) => connection.callOpenFile(
            "", dialogTitle ?? "flutter picker", options));
    // Maybe cancelled
    if (response == null || response.status != 0) {
      return null;
    }
    final uriPaths = _uris(response) ?? [];

    final filePaths = uriPaths.map((uri) => uri.toFilePath()).toList();

    final List<PlatformFile> platformFiles =
        await FilePickerUtils.filePathsToPlatformFiles(
      filePaths,
      withReadStream,
      withData,
    );

    return FilePickerResult(platformFiles);
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async {
    Map<String, DBusValue> xdpOption = {
      'directory': DBusBoolean(true),
      'modal': DBusBoolean(lockParentWindow),
    };
    if (initialDirectory != null) {
      final Uint8List tmp = _encodeDirectory(initialDirectory);
      DBusArray directory = DBusArray.byte(tmp);
      xdpOption["current_folder"] = directory;
    }
    final response = await _request(
        xdpOption,
        (connection, options) => connection.callOpenFile(
            "", dialogTitle ?? "flutter picker", options));
    // Maybe cancelled
    if (response == null || response.status != 0) {
      return null;
    }
    final uriPaths = _uris(response) ?? [];

    final filePaths = uriPaths.map((uri) => uri.toFilePath()).toList();

    final List<PlatformFile> platformFiles =
        await FilePickerUtils.filePathsToPlatformFiles(
      filePaths,
      false,
      false,
    );

    return platformFiles.firstOrNull?.path;
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    Map<String, DBusValue> xdpOption = {
      'current_name': DBusString(fileName ?? ''),
      'modal': DBusBoolean(lockParentWindow),
    };
    if (initialDirectory != null) {
      final Uint8List tmp = _encodeDirectory(initialDirectory);
      DBusArray directory = DBusArray.byte(tmp);
      xdpOption["current_folder"] = directory;
    }

    final response = await _request(
        xdpOption,
        (connection, options) => connection.callSaveFile(
            "", dialogTitle ?? "flutter picker", options));
    // Maybe cancelled
    if (response == null || response.status != 0) {
      return null;
    }
    final saveUris = _uris(response) ?? [];

    final savedFilePaths = saveUris.map((uri) => uri.toFilePath()).toList();
    final savedFilePath = savedFilePaths.firstOrNull;

    await FilePickerUtils.saveBytesToFile(bytes, savedFilePath);

    return savedFilePath;
  }

  List<Uri>? _uris(XdpResponse response) => response.results["uris"]
      ?.asArray()
      .map((data) => Uri.parse(data.asString()))
      .toList();

  /// Runs one portal request and returns its response, or null if it did not
  /// end within [responseTimeout].
  ///
  /// The portal may emit the Response before the method reply arrives, so the
  /// handle is derived from the unique name and handle_token and subscribed
  /// before [call] (see org.freedesktop.portal.Request).
  Future<XdpResponse?> _request(
    Map<String, DBusValue> options,
    Future<DBusObjectPath> Function(
            XdpPortalConnection connection, Map<String, DBusValue> options)
        call,
  ) async {
    final stopwatch = Stopwatch()..start();
    Duration remaining() => responseTimeout - stopwatch.elapsed;
    final token = 'flutter_picker_${_nextToken++}';
    final received = Completer<XdpResponse>();
    // A signal error may arrive while the method call fails as well; only the
    // await below reports it.
    received.future.ignore();
    void onResponse(XdpResponse response) {
      if (!received.isCompleted) received.complete(response);
    }

    void onError(Object error, StackTrace stackTrace) {
      if (!received.isCompleted) received.completeError(error, stackTrace);
    }

    final connection = _connectionFactory();
    final subscriptions = <StreamSubscription<XdpResponse>>[];
    DBusObjectPath? handle;
    try {
      final sender = await connection.connect().timeout(remaining());
      final expected = DBusObjectPath('/org/freedesktop/portal/desktop/request/'
          '${sender.replaceFirst(':', '').replaceAll('.', '_')}/$token');
      subscriptions.add(await connection
          .listenForResponse(expected, onResponse, onError)
          .timeout(remaining()));
      handle = expected;
      final returned = await call(
              connection, {...options, 'handle_token': DBusString(token)})
          .timeout(remaining());
      if (returned != expected) {
        // Portals before version 0.9 ignore handle_token. A response that
        // already arrived on the expected handle stays in [received].
        handle = returned;
        subscriptions.add(await connection
            .listenForResponse(returned, onResponse, onError)
            .timeout(remaining()));
      }
      return await received.future.timeout(remaining());
    } on TimeoutException {
      final open = handle;
      if (open != null) {
        await _bestEffort(() => connection.closeRequest(open));
      }
      return null;
    } finally {
      for (final subscription in subscriptions) {
        await _bestEffort(subscription.cancel);
      }
      await _bestEffort(connection.close);
    }
  }

  Future<void> _bestEffort(Future<void> Function() step) async {
    try {
      await step().timeout(_cleanupTimeout);
    } catch (_) {
      // Cleanup must not replace the result of the dialog.
    }
  }

  Uint8List _encodeDirectory(String initialDirectory) {
    return Uint8List.fromList([...utf8.encode(initialDirectory), 0]);
  }
}
