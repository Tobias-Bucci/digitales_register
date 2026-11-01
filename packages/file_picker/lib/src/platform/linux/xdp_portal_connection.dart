import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:file_picker/src/platform/linux/xdp_filechooser.dart';
import 'package:file_picker/src/platform/linux/xdp_request.dart';

/// A org.freedesktop.portal.Request.Response signal.
class XdpResponse {
  const XdpResponse(this.status, this.results);

  /// 0: success, 1: cancelled by the user, 2: ended in another way.
  final int status;
  final Map<String, DBusValue> results;
}

/// The part of the session bus that [FilePickerLinux] needs for one dialog.
///
/// The default implementation [DBusXdpPortalConnection] wraps a [DBusClient].
/// Tests substitute a fake, because signals cannot be delivered to a
/// [DBusClient] without a running bus.
abstract class XdpPortalConnection {
  /// Connects if necessary and returns the unique bus name of this connection.
  Future<String> connect();

  /// Listens for Request.Response signals of the portal on [handle].
  ///
  /// The returned future completes once every response emitted from then on
  /// is delivered to [onResponse].
  Future<StreamSubscription<XdpResponse>> listenForResponse(
    DBusObjectPath handle,
    void Function(XdpResponse response) onResponse,
    void Function(Object error, StackTrace stackTrace) onError,
  );

  /// Invokes org.freedesktop.portal.FileChooser.OpenFile().
  Future<DBusObjectPath> callOpenFile(
      String parentWindow, String title, Map<String, DBusValue> options);

  /// Invokes org.freedesktop.portal.FileChooser.SaveFile().
  Future<DBusObjectPath> callSaveFile(
      String parentWindow, String title, Map<String, DBusValue> options);

  /// Invokes org.freedesktop.portal.Request.Close() on [handle].
  Future<void> closeRequest(DBusObjectPath handle);

  /// Closes the connection.
  Future<void> close();
}

class DBusXdpPortalConnection implements XdpPortalConnection {
  DBusXdpPortalConnection(this.client);

  static const destination = 'org.freedesktop.portal.Desktop';

  final DBusClient client;
  late final _chooser = OrgFreedesktopPortalFileChooser(client, destination,
      path: DBusObjectPath('/org/freedesktop/portal/desktop'));
  String? _portalOwner;

  @override
  Future<String> connect() async {
    // Response signals carry the portal's unique name as sender. Resolving it
    // up front lets the subscription filter by it without the client's own
    // asynchronous name lookup, which can lag behind an early signal.
    var owner = await client.getNameOwner(destination);
    if (owner == null) {
      // The portal is D-Bus activated; OpenFile would otherwise start it.
      await client.startServiceByName(destination);
      owner = await client.getNameOwner(destination);
    }
    if (owner == null) {
      throw StateError('$destination is not available on the session bus');
    }
    _portalOwner = owner;
    return client.uniqueName;
  }

  @override
  Future<StreamSubscription<XdpResponse>> listenForResponse(
    DBusObjectPath handle,
    void Function(XdpResponse response) onResponse,
    void Function(Object error, StackTrace stackTrace) onError,
  ) async {
    final owner = _portalOwner;
    final subscription = DBusSignalStream(client,
            interface: 'org.freedesktop.portal.Request',
            name: 'Response',
            path: handle,
            signature: DBusSignature('ua{sv}'))
        .where((signal) => signal.sender == owner)
        .map((signal) {
      final response = OrgFreedesktopPortalRequestResponse(signal);
      return XdpResponse(response.response, response.results);
    }).listen(onResponse, onError: onError);
    // Listening sends AddMatch without exposing its completion. The bus
    // handles the messages of one connection in order, so once this ping is
    // answered the match rule is active.
    await client.ping();
    return subscription;
  }

  @override
  Future<DBusObjectPath> callOpenFile(
          String parentWindow, String title, Map<String, DBusValue> options) =>
      _chooser.callOpenFile(parentWindow, title, options);

  @override
  Future<DBusObjectPath> callSaveFile(
          String parentWindow, String title, Map<String, DBusValue> options) =>
      _chooser.callSaveFile(parentWindow, title, options);

  @override
  Future<void> closeRequest(DBusObjectPath handle) =>
      OrgFreedesktopPortalRequest(client, destination, path: handle)
          .callClose();

  @override
  Future<void> close() => client.close();
}
