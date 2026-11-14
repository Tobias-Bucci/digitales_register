// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// The web app cannot talk to the school servers directly: they send no CORS
/// headers. It talks to them through the same-origin proxy of the server that
/// serves the web app (a Cloudflare Worker on app.digitalesregister.com):
///
/// `https://<school>.digitalesregister.it/v2/...` becomes
/// `<app origin>/proxy/<school>.digitalesregister.it/<slot>/v2/...`.
///
/// The browser keeps the school's cookies, scoped by the proxy to
/// `/proxy/<school>/<slot>/`. Each session has its own slot, like each
/// session of the native app has its own cookie jar, so two sessions (an
/// account switch, a logout that is still running) never share or delete each
/// other's cookies. The native app is not affected by anything in this file.
bool get usesSchoolProxy => kIsWeb;

final _schoolHost =
    RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.digitalesregister\.it$');

/// Whether the proxy serves [host]. It accepts exactly these hosts.
bool isProxiedSchoolHost(String host) => _schoolHost.hasMatch(host);

/// Response header set by the proxy on everything it answers, errors included.
const proxyMarkerHeader = 'x-dr-proxy';

const _slotAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// A new random cookie slot (`s-` and 16 characters).
String newProxySlot([Random? random]) {
  final r = random ?? Random.secure();
  return 's-${List.generate(16, (_) => _slotAlphabet[r.nextInt(36)]).join()}';
}

/// The proxy address for [url], or null if the proxy does not serve it.
/// [origin] is the web app's own origin, `Uri.base.origin` in the browser.
String? proxiedSchoolUrl(String url, String slot, {required String origin}) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443) ||
      !isProxiedSchoolHost(uri.host)) {
    return null;
  }
  final path = uri.path.isEmpty ? '/' : uri.path;
  final query = uri.hasQuery ? '?${uri.query}' : '';
  return '$origin/proxy/${uri.host}/$slot$path$query';
}

/// Address that deletes every cookie of a slot at the proxy.
String proxyClearCookiesUrl(String host, String slot,
        {required String origin}) =>
    '$origin/proxy/$host/$slot/__dr/clear-cookies';

final Dio _clearClient = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 15),
));

/// Deletes the cookies of [slot] for [host] at the proxy. Never throws.
Future<void> clearProxyCookies(String host, String slot) async {
  if (!usesSchoolProxy || !isProxiedSchoolHost(host)) return;
  try {
    await _clearClient
        .post<void>(proxyClearCookiesUrl(host, slot, origin: Uri.base.origin));
  } catch (_) {
    // Best effort: the cookies are session cookies of a session that has
    // ended anyway, and the slot is never used again.
  }
}

/// Where [cannotConnectTo] checks the connection in the web build: the
/// school through the proxy, or the web app's own server.
String webConnectivityProbeUrl(String url) =>
    proxiedSchoolUrl(url, 's-connectivityprobe', origin: Uri.base.origin) ??
    '${Uri.base.origin}/version.json';

/// Whether a response to a proxied address came from Cloudflare instead of
/// the proxy, because the daily quota is used up.
bool isProxyQuotaResponse(int status, String? marker) =>
    marker == null && (status == 429 || status == 403 || status >= 500);

/// The proxy is out of service for today, see [SchoolProxyInterceptor].
class SchoolProxyUnavailable implements Exception {
  const SchoolProxyUnavailable();
  @override
  String toString() => 'school proxy unavailable';
}

/// Notified once each time the proxy turns out to be unavailable, so the app
/// can tell the user. Set by the app; tests leave it null.
VoidCallback? onSchoolProxyUnavailable;

/// Sends every request to a school through the proxy. Requests to any other
/// address are left alone.
///
/// When the proxy's daily free quota is used up, Cloudflare answers itself
/// (status 429 or an error page with code 1027) and that answer lacks
/// [proxyMarkerHeader]. Such answers become [SchoolProxyUnavailable], so the
/// app can say "temporarily unavailable" instead of "no internet".
class SchoolProxyInterceptor extends Interceptor {
  SchoolProxyInterceptor(this._slot,
      {this.onProxied, String Function()? origin})
      : _origin = origin ?? (() => Uri.base.origin);

  final String Function() _slot;
  final String Function() _origin;

  /// Called with the school host of every request sent through the proxy.
  final void Function(String host)? onProxied;

  static const _proxiedExtra = 'drSchoolProxy';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final target = options.uri;
    final proxied =
        proxiedSchoolUrl(target.toString(), _slot(), origin: _origin());
    // Without a school (an empty address, as in demo mode) the native app's
    // request fails for lack of a host. In the browser such a relative URL
    // would reach the web app's own server instead, so it fails here too.
    if (proxied == null && (!target.hasAuthority || target.host.isEmpty)) {
      handler.reject(DioException(
        requestOptions: options,
        error: ArgumentError('No school address in $target'),
      ));
      return;
    }
    if (proxied != null) {
      onProxied?.call(target.host);
      options
        ..baseUrl = ''
        ..path = proxied
        ..queryParameters = <String, dynamic>{}
        ..extra[_proxiedExtra] = true;
    }
    handler.next(options);
  }

  bool _fromCloudflareInstead(Response<dynamic>? response) {
    if (response == null) return false;
    if (response.requestOptions.extra[_proxiedExtra] != true) return false;
    return isProxyQuotaResponse(
        response.statusCode ?? 0, response.headers.value(proxyMarkerHeader));
  }

  DioException _unavailable(RequestOptions options, Response<dynamic>? r) {
    onSchoolProxyUnavailable?.call();
    return DioException(
      requestOptions: options,
      response: r,
      error: const SchoolProxyUnavailable(),
    );
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (_fromCloudflareInstead(response)) {
      handler.reject(_unavailable(response.requestOptions, response));
      return;
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_fromCloudflareInstead(err.response)) {
      handler.next(_unavailable(err.requestOptions, err.response));
      return;
    }
    handler.next(err);
  }
}
