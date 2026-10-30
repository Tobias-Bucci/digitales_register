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

/// The school server and user name a session belongs to.
///
/// The server is compared canonically (scheme and host in lower case, no
/// trailing slashes). The user name is compared exactly: it is not known
/// whether a school server treats `Max` and `max` as one account, so they stay
/// two scopes. That can duplicate data but never mixes the data of accounts.
class AccountScope {
  AccountScope(String? server, this.user) : server = _canonicalServer(server);

  final String server;
  final String? user;

  static String _canonicalServer(String? server) {
    final trimmed = (server ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return trimmed;
    return uri
        .replace(scheme: uri.scheme.toLowerCase(), host: uri.host.toLowerCase())
        .toString();
  }

  @override
  bool operator ==(Object other) =>
      other is AccountScope && other.server == server && other.user == user;

  @override
  int get hashCode => Object.hash(server, user);

  // Deliberately without the user name: scopes end up in diagnostics.
  @override
  String toString() => 'AccountScope($server)';
}
