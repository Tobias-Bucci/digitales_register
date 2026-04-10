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

final _profileMiddleware = MiddlewareBuilder<AppState, AppStateBuilder,
    AppActions>()
  ..add(ProfileActionsNames.load, _loadProfile)
  ..add(ProfileActionsNames.sendNotificationEmails, _setSendNotificationEmails)
  ..add(ProfileActionsNames.changeEmail, _changeEmail)
  ..add(
    ProfileActionsNames.pickAndUploadProfilePicture,
    _pickAndUploadProfilePicture,
  )
  ..add(ProfileActionsNames.updateCodiceFiscale, _updateCodiceFiscale);

typedef ProfilePicturePicker = Future<SelectedProfilePicture?> Function();

@visibleForTesting
ProfilePicturePicker pickProfilePicture = _defaultPickProfilePicture;

class SelectedProfilePicture {
  const SelectedProfilePicture({
    required this.bytes,
    required this.contentType,
    required this.fileName,
  });

  final List<int> bytes;
  final String contentType;
  final String fileName;
}

Future<void> _loadProfile(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  await next(action);
  if (api.state.noInternet) return;
  dynamic result;
  try {
    result = await wrapper.send("api/profile/get");
  } on UnexpectedLogoutException {
    _showProfileRequestFailedMessage(
      tr('profile.loadFailed'),
    );
    return;
  }
  if (result == null) {
    return;
  }
  final resultMap = getMap(result);
  if (resultMap != null) {
    await _syncServerLanguageToApp(
      api: api,
      profile: resultMap,
    );
  }
  await api.actions.profileActions.loaded(result as Object);
}

Future<void> _syncServerLanguageToApp({
  required MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  required Map profile,
}) async {
  final targetLanguage =
      _preferredServerLanguageForApp(api.state.settingsState.languageCode);
  if (targetLanguage == null) {
    return;
  }

  final serverLanguage = getString(profile['language'])?.trim().toLowerCase();
  if (serverLanguage == null || serverLanguage == targetLanguage) {
    return;
  }

  try {
    await wrapper.send(
      'api/profile/updateProfile',
      args: <String, Object?>{
        'language': targetLanguage,
      },
    );
  } catch (_) {
    // Best effort only. If the server rejects this, keep the local app language.
  }
}

bool _isServerLanguageSupported(String languageCode) {
  return languageCode == 'de' || languageCode == 'it' || languageCode == 'en';
}

String? _preferredServerLanguageForApp(String languageCode) {
  if (_isServerLanguageSupported(languageCode)) {
    return languageCode;
  }
  if (languageCode == 'lld') {
    return 'de';
  }
  return null;
}

Future<void> _setSendNotificationEmails(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<bool> action) async {
  dynamic result;
  try {
    result = await wrapper.send(
      "api/profile/updateNotificationSettings",
      args: {
        "notificationsEnabled": action.payload,
      },
    );
  } on UnexpectedLogoutException {
    _showProfileRequestFailedMessage(
      tr('profile.notificationSettingsFailed'),
    );
    return;
  }
  if (result == null) {
    return;
  }
  await next(action);
}

Future<void> _changeEmail(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<ChangeEmailPayload> action) async {
  await next(action);
  dynamic result;
  try {
    result = await wrapper.send(
      "api/profile/updateProfile",
      args: {
        "email": action.payload.email,
        "password": action.payload.pass,
      },
    );
  } on UnexpectedLogoutException {
    _showProfileRequestFailedMessage(
      tr('profile.saveFailed'),
    );
    return;
  }
  if (result == null) {
    return;
  }
  if (result["error"] == null) {
    showSnackBar(result["message"] as String);
    navigatorKey?.currentState?.pop();
  } else {
    showSnackBar("[${result["error"]}]: ${result["message"]}");
  }
  await api.actions.profileActions.load();
}

Future<void> _pickAndUploadProfilePicture(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  await next(action);
  final selected = await pickProfilePicture();
  if (selected == null) {
    return;
  }

  dynamic result;
  try {
    result = await wrapper.sendBytes(
      "api/profile/uploadProfilePicture",
      bytes: selected.bytes,
      contentType: selected.contentType,
      fileName: selected.fileName,
    );
  } on UnexpectedLogoutException {
    _showProfileRequestFailedMessage(
      tr('profile.pictureUploadFailed'),
    );
    return;
  }
  if (result == null) {
    return;
  }

  final resultMap = getMap(result);
  if (resultMap == null) {
    showSnackBar(tr('profile.pictureUploadFailed'));
    return;
  }

  if (resultMap["error"] == null) {
    showSnackBar(tr('profile.pictureUpdated'));
    await api.actions.profileActions.load();
  } else {
    showSnackBar("[${resultMap["error"]}] ${resultMap["message"]}");
  }
}

Future<void> _updateCodiceFiscale(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<String> action) async {
  await next(action);
  if (api.state.profileState.codiceFiscale?.trim().isNotEmpty ?? false) {
    showSnackBar(
      tr('profile.taxIdLocked'),
    );
    return;
  }

  final codiceFiscale = action.payload.trim().toUpperCase();
  if (codiceFiscale.isEmpty) {
    return;
  }

  dynamic result;
  try {
    result = await wrapper.send(
      "api/profile/updateCodiceFiscale",
      args: <String, Object?>{
        "codiceFiscale": codiceFiscale,
      },
    );
  } on UnexpectedLogoutException {
    _showProfileRequestFailedMessage(
      tr('profile.taxIdSaveFailed'),
    );
    return;
  }
  if (result == null) {
    return;
  }

  final resultMap = getMap(result);
  if (resultMap == null) {
    showSnackBar(tr('profile.taxIdSaveFailed'));
    return;
  }

  if (resultMap["error"] == null) {
    showSnackBar(
      getString(resultMap["message"]) ?? tr('profile.taxIdUpdated'),
    );
    await api.actions.profileActions.load();
  } else {
    showSnackBar("[${resultMap["error"]}]: ${resultMap["message"]}");
  }
}

void _showProfileRequestFailedMessage(String message) {
  if (!wrapper.noInternet) {
    showSnackBar(message);
  }
}

Future<SelectedProfilePicture?> _defaultPickProfilePicture() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
  );
  if (result == null || result.files.isEmpty) {
    return null;
  }

  final file = result.files.single;
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) {
    final path = file.path;
    if (path == null || path.isEmpty) {
      return null;
    }
    return SelectedProfilePicture(
      bytes: await File(path).readAsBytes(),
      contentType: _guessImageMimeType(file.name),
      fileName: file.name,
    );
  }

  return SelectedProfilePicture(
    bytes: bytes,
    contentType: _guessImageMimeType(file.name),
    fileName: file.name,
  );
}

String _guessImageMimeType(String fileName) {
  final normalized = fileName.toLowerCase();
  if (normalized.endsWith('.png')) {
    return 'image/png';
  }
  if (normalized.endsWith('.gif')) {
    return 'image/gif';
  }
  if (normalized.endsWith('.webp')) {
    return 'image/webp';
  }
  return 'image/jpeg';
}
