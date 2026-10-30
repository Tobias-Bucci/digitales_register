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

Future<void> _removePreference(String key) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(key);
}

LocalDataEntry _preferenceEntry(
  String id,
  String namespace, {
  required LocalDataCategory category,
  required Set<LocalDataTrigger> deletedBy,
  bool gated = false,
}) =>
    LocalDataEntry(
      id: id,
      category: category,
      deletedBy: deletedBy,
      gatedByNoDataSaving: gated,
      deleteFor: (account) =>
          _removePreference('$namespace:${account.storageKey}'),
    );

/// The places the app keeps data of an account, and what deletes each.
///
/// Not in the list on purpose: the settings shared by all accounts, the
/// saved sign-in, and what other apps and the device keep (see the entries
/// for exports and downloads). Every way of deleting goes through this list.
final LocalDataInventory localDataInventory = LocalDataInventory([
  // The saved state of the account. Turning off saving and deleting data
  // overwrite it with the settings alone when the state is saved next.
  LocalDataEntry(
    id: 'accountState',
    category: LocalDataCategory.appOwnedCache,
    deletedBy: {LocalDataTrigger.removeAccount},
    deleteFor: (account) =>
        secureStorage.delete(key: escapeKey(account.storageKey)),
  ),
  // Caches that make the app faster: not kept while saving is off.
  _preferenceEntry(
    'homeworkSummaryCache',
    'homeworkSummary',
    category: LocalDataCategory.appOwnedCache,
    deletedBy: {
      LocalDataTrigger.removeAccount,
      LocalDataTrigger.deleteData,
      LocalDataTrigger.stopSaving,
    },
    gated: true,
  ),
  _preferenceEntry(
    'classRegisterCache',
    'classRegisterLessons',
    category: LocalDataCategory.appOwnedCache,
    deletedBy: {
      LocalDataTrigger.removeAccount,
      LocalDataTrigger.deleteData,
      LocalDataTrigger.stopSaving,
    },
    gated: true,
  ),
  _preferenceEntry(
    'courseMaterialsCache',
    'courseMaterials',
    category: LocalDataCategory.appOwnedCache,
    deletedBy: {
      LocalDataTrigger.removeAccount,
      LocalDataTrigger.deleteData,
      LocalDataTrigger.stopSaving,
    },
    gated: true,
  ),
  // What the user entered or wrote: deleted with the account and when data is
  // deleted, but not when saving of data is turned off.
  _preferenceEntry(
    'gradeDeadlineOverrides',
    'gradeDeadlineOverrides',
    category: LocalDataCategory.userCreated,
    deletedBy: {LocalDataTrigger.removeAccount, LocalDataTrigger.deleteData},
  ),
  LocalDataEntry(
    id: 'studyData',
    category: LocalDataCategory.userCreated,
    deletedBy: {LocalDataTrigger.removeAccount, LocalDataTrigger.deleteData},
    deleteFor: (account) async {
      if (_studyDataScope == account.scope) _studyDataScope = null;
      await studyDataService.delete(account.scope);
    },
  ),
  LocalDataEntry(
    id: 'studyFiles',
    category: LocalDataCategory.userCreated,
    deletedBy: {LocalDataTrigger.removeAccount, LocalDataTrigger.deleteData},
    deleteFor: (account) => deleteAssessmentAttachmentFolder(account.scope),
  ),
  // Copies Android makes to hand a study file to a viewer; they belong to the
  // study files and go with them.
  LocalDataEntry(
    id: 'studyFileOpenCopies',
    category: LocalDataCategory.appOwnedCache,
    deletedBy: {LocalDataTrigger.removeAccount, LocalDataTrigger.deleteData},
    deleteFor: (_) => deleteAssessmentOpenCopies(),
  ),
  // Documents the user downloaded stay when data is deleted: they are the
  // user's files in a folder the user can see. Only removing the account
  // removes the account's folder.
  LocalDataEntry(
    id: 'downloads',
    category: LocalDataCategory.download,
    deletedBy: {LocalDataTrigger.removeAccount},
    deleteFor: (account) => _deleteAccountDownloads(account.scope),
  ),
  LocalDataEntry(
    id: 'downloadVersions',
    category: LocalDataCategory.appOwnedCache,
    deletedBy: {LocalDataTrigger.removeAccount},
    deleteFor: (account) =>
        _removePreference(_courseMaterialVersionsKeyFor(account.scope)),
  ),
  LocalDataEntry(
    id: 'schoolNotificationState',
    category: LocalDataCategory.appOwnedCache,
    deletedBy: {LocalDataTrigger.removeAccount},
    deleteFor: (account) => schoolNotificationOperation(
        () => schoolNotifications.forgetAccount(
            account.scope.server, account.scope.user!)),
  ),
  // Events the app wrote into the calendar of the device, and the list of
  // which ones they are. Nothing deletes them but the user's own action in
  // the settings: they live outside the app, and the list is what lets the
  // app find them again.
  LocalDataEntry(
    id: 'calendarSyncRecords',
    category: LocalDataCategory.export,
    deletedBy: const {},
    deleteFor: (_) async {},
  ),
]);

/// The account that is signed in now, for deleting its data.
LocalDataAccount? _currentLocalDataAccount(AppState state) {
  final user = state.loginState.username;
  if (!state.loginState.loggedIn || user == null) return null;
  return LocalDataAccount(
    scope: _studyScopeOf(user),
    storageKey: getStorageKey(user, wrapper.loginAddress),
  );
}

/// Deletes what [trigger] deletes for the account that is signed in, behind
/// every write already requested.
Future<void> _deleteCurrentAccountData(
  AppState state,
  LocalDataTrigger trigger,
) async {
  final account = _currentLocalDataAccount(state);
  if (account == null) return;
  await statePersistenceService
      .runExclusive(() => localDataInventory.deleteForAccount(account, trigger));
}
