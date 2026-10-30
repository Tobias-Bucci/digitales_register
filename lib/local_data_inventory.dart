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

import 'package:dr/account_scope.dart';
import 'package:flutter/foundation.dart';

/// What the app may keep on the device right now.
///
/// Caches that only make the app faster consult this where they write, not
/// where they are asked to write: a new caller cannot forget it.
class LocalDataPolicy {
  /// Whether the user turned off saving of data. Set by the store.
  bool Function() noDataSavingReader = () => false;

  /// Whether the data of the account is being deleted, so that nothing that
  /// finishes later may bring it back.
  bool dataDeletionActive = false;

  bool get noDataSaving => noDataSavingReader();

  /// Whether a cache may be written. The settings the user chose and the
  /// notes the user wrote are not caches and do not ask.
  bool get mayStoreCaches => !noDataSaving && !dataDeletionActive;

  /// Back to the defaults, for tests.
  void reset() {
    noDataSavingReader = () => false;
    dataDeletionActive = false;
  }
}

final LocalDataPolicy localDataPolicy = LocalDataPolicy();

/// What kind of data a [LocalDataEntry] is.
enum LocalDataCategory {
  /// Kept only to make the app faster or work offline; can be fetched again.
  appOwnedCache,

  /// Written by the user; it exists nowhere else.
  userCreated,

  /// A copy the app put outside itself, e.g. into the calendar of the device.
  export,

  /// A document the user downloaded.
  download,
}

/// What makes the app delete an entry.
enum LocalDataTrigger {
  /// The account is removed from the device.
  removeAccount,

  /// The user signs out with deletion of data, or the data is deleted.
  deleteData,

  /// The user turns off saving of data.
  stopSaving,
}

/// The account whose data is deleted, as the places it is kept know it.
@immutable
class LocalDataAccount {
  const LocalDataAccount({required this.scope, required this.storageKey});

  final AccountScope scope;

  /// The key under which the saved state and the cache namespaces of the
  /// account are kept (`getStorageKey`).
  final String storageKey;
}

/// One place the app keeps data, and what deletes it.
class LocalDataEntry {
  const LocalDataEntry({
    required this.id,
    required this.category,
    required this.deletedBy,
    required this.deleteFor,
    this.gatedByNoDataSaving = false,
  });

  final String id;
  final LocalDataCategory category;

  /// The triggers that delete this entry. Empty: only an explicit action of
  /// the user does, and the texts must not promise otherwise.
  final Set<LocalDataTrigger> deletedBy;

  /// Whether the entry is not written while saving of data is turned off.
  final bool gatedByNoDataSaving;

  final Future<void> Function(LocalDataAccount account) deleteFor;
}

/// Every place the app keeps data of an account, in one list, so that every
/// way of deleting runs the same code and a place that is added is not
/// forgotten by one of them.
class LocalDataInventory {
  const LocalDataInventory(this.entries);

  final List<LocalDataEntry> entries;

  /// Deletes what [trigger] deletes for [account]. One entry failing does not
  /// stop the others; the first failure is thrown afterwards.
  Future<void> deleteForAccount(
    LocalDataAccount account,
    LocalDataTrigger trigger,
  ) async {
    Object? firstError;
    StackTrace? firstStack;
    for (final entry in entries) {
      if (!entry.deletedBy.contains(trigger)) continue;
      try {
        await entry.deleteFor(account);
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }
}
