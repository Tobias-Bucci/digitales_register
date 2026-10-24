// Copyright (C) 2021 Michael Debertol
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

part of 'middleware.dart';

final _passMiddleware =
    MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
      ..add(SettingsActionsNames.saveNoPass, _setSavePass)
      ..add(SavePassActionsNames.save, _savePass)
      ..add(SavePassActionsNames.delete, _deletePass);

Future<void> _setSavePass(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<bool> action) async {
  await next(action);
  wrapper.safeMode = action.payload;
  if (!api.state.loginState.loggedIn) return;
  // This setting controls automatic sign-in, not removal from the account list.
  await api.actions.savePassActions.save();
  if (wrapper.url != null && wrapper.user != null && !wrapper.demoMode) {
    await schoolNotificationOperation(() => schoolNotifications.activate(
        wrapper.url!, wrapper.user!,
        backgroundAllowed: !action.payload));
  }
}

Future<void> _savePass(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next, Action<void> action) async {
  await next(action);
  if (wrapper.user == null || wrapper.pass == null) {
    return;
  }

  // If the user is logged in as 'debug', save 'debug' instead of the mapped username ('stbuctob').
  final userToSave =
      api.state.loginState.username == 'debug' ? 'debug' : wrapper.user;
  final login = decodeStoredLogin(await secureStorage.read(key: 'login'));
  final otherAccounts = (login['otherAccounts'] as List? ?? <Object?>[])
      .where((dynamic account) =>
          account['user'] != userToSave || account['url'] != wrapper.url)
      .toList();
  if (login['user'] != null &&
      login['pass'] != null &&
      (login['user'] != userToSave || login['url'] != wrapper.url) &&
      !otherAccounts.any((dynamic account) =>
          account['user'] == login['user'] && account['url'] == login['url'])) {
    otherAccounts.insert(0, <String, Object?>{
      'user': login['user'],
      'pass': login['pass'],
      'url': login['url'],
    });
  }

  await secureStorage.write(
    key: "login",
    value: json.encode(
      <String, Object?>{
        "user": userToSave,
        "pass": wrapper.pass,
        "url": wrapper.url,
        "otherAccounts": otherAccounts,
      },
    ),
  );
  await api.actions.loginActions.setAvailableAccounts(
    otherAccounts.map((dynamic account) => account['user'] as String).toList(),
  );
}

Future<void> _deletePass(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  await next(action);
  await secureStorage.write(
    key: "login",
    value: json.encode(
      <String, Object?>{
        "url": wrapper.url,
        "otherAccounts": json.decode(
            await secureStorage.read(key: "login") ?? "{}")["otherAccounts"],
      },
    ),
  );
}
