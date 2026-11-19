import 'dart:convert';

import 'package:dr/diagnostics_service.dart';

/// The key of the saved login block that marks its account as signed out.
///
/// The user signed out of the account but kept it on the device: its
/// credentials stay, it is listed on the sign-in screen, and the app does not
/// sign in with it on its own. Removing the account deletes it.
const signedOutKey = 'signedOut';

/// Validates the encrypted login block, preserving independent valid accounts.
/// The URL-only block is also valid after an explicit logout that forgets the
/// account (on the web, in the demo, or when the session expired).
Map<String, dynamic> decodeStoredLogin(String? raw) {
  if (raw == null) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid saved login structure');
    }
    var damaged = decoded.containsKey('url') && decoded['url'] is! String;
    bool validAccount(dynamic value) =>
        value is Map &&
        value['user'] is String &&
        (value['user'] as String).isNotEmpty &&
        value['pass'] is String &&
        (value['pass'] as String).isNotEmpty &&
        value['url'] is String;
    final result = <String, dynamic>{};
    if (decoded['url'] is String) result['url'] = decoded['url'];
    if (decoded.containsKey('user') || decoded.containsKey('pass')) {
      if (validAccount(decoded)) {
        result.addAll({
          'user': decoded['user'],
          'pass': decoded['pass'],
          if (decoded[signedOutKey] == true) signedOutKey: true,
        });
      } else {
        damaged = true;
      }
    }
    final accounts = decoded['otherAccounts'];
    if (accounts is List) {
      result['otherAccounts'] = <Map<String, dynamic>>[
        for (final account in accounts)
          if (validAccount(account))
            <String, dynamic>{
              'user': account['user'],
              'pass': account['pass'],
              'url': account['url'],
            }
      ];
      damaged |= (result['otherAccounts'] as List).length != accounts.length;
    } else if (accounts != null) {
      damaged = true;
    }
    if (damaged) {
      diagnostics.report(const FormatException('Invalid saved account'),
          StackTrace.current, DiagnosticError.storage);
    }
    return result;
  } catch (error, stack) {
    diagnostics.report(error, stack, DiagnosticError.storage);
    return <String, dynamic>{};
  }
}

/// Whether the primary account of [login] is shown in the list of saved
/// accounts on the sign-in screen, instead of being signed in on its own:
/// "stay signed in" is off, or the user signed out of it.
///
/// While signed in, the list holds only the other accounts.
bool primaryAccountListed(
  Map<dynamic, dynamic> login, {
  required bool loggedIn,
  required bool noPasswordSaving,
}) =>
    !loggedIn &&
    (noPasswordSaving || login[signedOutKey] == true) &&
    login['user'] != null &&
    login['pass'] != null &&
    login['url'] != null;
