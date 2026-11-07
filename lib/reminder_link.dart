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

final _whitespace = RegExp(r'\s');
final _otherScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:(?!\d+(?:[/?#]|$))');

/// The link a reminder should open, from what the user typed.
///
/// Returns an empty string for empty input, which means no link, and null for
/// anything that is not a usable http or https address. An address without a
/// scheme gets https://, as long as it has a dot and so looks like a domain.
/// Other schemes are refused, and so is a user name in front of the host, which
/// only serves to disguise where a link leads.
String? normalizeReminderLink(String input) {
  final text = input.trim();
  if (text.isEmpty) return '';
  if (text.contains(_whitespace)) return null;
  final hasScheme = text.contains('://');
  if (!hasScheme && _otherScheme.hasMatch(text)) return null;
  final uri = Uri.tryParse(hasScheme ? text : 'https://$text');
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.userInfo.isNotEmpty) return null;
  final host = uri.host;
  if (host.isEmpty ||
      host.startsWith('.') ||
      host.endsWith('.') ||
      host.contains('..')) {
    return null;
  }
  if (!hasScheme && !host.contains('.')) return null;
  return uri.toString();
}
