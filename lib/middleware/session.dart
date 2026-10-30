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

/// Counts every replacement of the global [wrapper]. Two sessions of the same
/// account (A, B, A again) still differ by their generation.
int _sessionGeneration = 0;

/// Thrown when work started by one session finishes after the app has left it.
///
/// It is not an error: whatever the work produced belongs to an account that is
/// no longer shown, so it must be dropped without a message, a failure state or
/// a report. [_runCoalescedLoad] and [_staleSessionMiddleware] absorb it.
class StaleSessionException implements Exception {
  const StaleSessionException();

  @override
  String toString() => 'StaleSessionException';
}

/// The wrapper of the session the app is in right now.
Wrapper _currentWrapper() => wrapper;

/// The session an asynchronous operation was started in.
///
/// Capture it before the first `await` of a load or mutation and send through
/// it: the request then goes out on the session that started it, and its
/// result is dropped (by [StaleSessionException]) once the app has switched
/// account, logged out or retired that session.
class _Session {
  _Session._(this.wrapper, this.scope, this.generation, this._storageKey);

  factory _Session.capture({bool withStorageKey = false}) {
    final wrapper = _currentWrapper();
    return _Session._(
      wrapper,
      AccountScope(wrapper.url, wrapper.user),
      _sessionGeneration,
      withStorageKey ? getStorageKey(wrapper.user, wrapper.loginAddress) : null,
    );
  }



  final Wrapper wrapper;
  final AccountScope scope;
  final int generation;

  final String? _storageKey;

  /// The key the account's saved data uses, fixed when the session started
  /// (capture with `withStorageKey`). Computing it after an `await` would use
  /// whoever is signed in by then.
  String get storageKey => _storageKey!;

  bool get isCurrent {
    if (generation != _sessionGeneration ||
        !identical(wrapper, _currentWrapper()) ||
        wrapper.isRetired) {
      return false;
    }
    final current = AccountScope(wrapper.url, wrapper.user);
    // A session that started before the sign-in finished has no user yet.
    return current.server == scope.server &&
        (scope.user == null || scope.user == current.user);
  }

  void ensureCurrent() {
    if (!isCurrent) throw const StaleSessionException();
  }

  /// Like [Wrapper.send]; only the arguments the caller gave are forwarded.
  Future<dynamic> send(
    String url, {
    Map<String, Object?>? args,
    String? method,
    bool? acceptEmptyResponse,
  }) async {
    ensureCurrent();
    try {
      final result = await Function.apply(
        wrapper.send,
        <Object?>[url],
        <Symbol, Object?>{
          if (args != null) #args: args,
          if (method != null) #method: method,
          if (acceptEmptyResponse != null)
            #acceptEmptyResponse: acceptEmptyResponse,
        },
      );
      ensureCurrent();
      return result;
    } catch (_) {
      // Whatever went wrong, a session we have left must stay silent.
      ensureCurrent();
      rethrow;
    }
  }

  Future<dynamic> sendBytes(
    String url, {
    required List<int> bytes,
    required String contentType,
    required String fileName,
  }) async {
    ensureCurrent();
    try {
      final result = await wrapper.sendBytes(
        url,
        bytes: bytes,
        contentType: contentType,
        fileName: fileName,
      );
      ensureCurrent();
      return result;
    } catch (_) {
      ensureCurrent();
      rethrow;
    }
  }
}

/// Absorbs [StaleSessionException] before the diagnostics and analytics
/// middleware see it as a failed action.
NextActionHandler _staleSessionMiddleware(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
) =>
    (ActionHandler next) => (Action action) async {
          try {
            await next(action);
          } on StaleSessionException {
            // The account was left while the action ran.
          }
        };
