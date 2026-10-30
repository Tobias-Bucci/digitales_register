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

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The one spelling of a school server that accounts are compared by: scheme
/// and host in lower case, no trailing slashes. Everything that tells accounts
/// apart (scopes, notification keys) must go through here.
String canonicalSchoolServer(String? server) {
  final trimmed = (server ?? '').trim().replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) return trimmed;
  return uri
      .replace(scheme: uri.scheme.toLowerCase(), host: uri.host.toLowerCase())
      .toString();
}

/// The school server and user name a session belongs to.
///
/// The server is compared canonically (scheme and host in lower case, no
/// trailing slashes). The user name is compared exactly: it is not known
/// whether a school server treats `Max` and `max` as one account, so they stay
/// two scopes. That can duplicate data but never mixes the data of accounts.
class AccountScope {
  AccountScope(String? server, this.user)
      : server = canonicalSchoolServer(server);

  /// The scope of the demo account. It has no school server and is never the
  /// scope of a real account, so nothing saved for it is shared with one.
  AccountScope.demo()
      : server = '',
        user = 'demo';

  final String server;
  final String? user;

  /// A name for files, folders and storage keys of this account: the first 32
  /// hex digits of the SHA-256 of the server and user. Unlike the user name or
  /// the saved-state key it contains no characters a file system rejects, it
  /// is the same on every platform, and it reveals neither school nor user.
  String get fileId => sha256
      .convert(utf8.encode(jsonEncode(<String?>[server, user])))
      .toString()
      .substring(0, 32);

  @override
  bool operator ==(Object other) =>
      other is AccountScope && other.server == server && other.user == user;

  @override
  int get hashCode => Object.hash(server, user);

  // Deliberately without the user name: scopes end up in diagnostics.
  @override
  String toString() => 'AccountScope($server)';
}
