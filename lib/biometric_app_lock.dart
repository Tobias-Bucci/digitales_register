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

import 'dart:async';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:dr/main.dart';
import 'package:flutter/material.dart';

const _appLockStorageName = 'biometric_app_lock';
const _appLockEnabledMarker = 'enabled';

const _appLockPromptInfo = PromptInfo(
  androidPromptInfo: AndroidPromptInfo(
    title: 'Digitales Register entsperren',
    subtitle: 'Biometrische Sperre',
    description: 'Bitte authentifiziere dich, um die App zu öffnen.',
    negativeButton: 'Abbrechen',
    confirmationRequired: false,
  ),
  iosPromptInfo: IosPromptInfo(
    saveTitle: 'Biometrische Sperre aktivieren',
    accessTitle: 'Digitales Register entsperren',
  ),
  macOsPromptInfo: IosPromptInfo(
    saveTitle: 'Biometrische Sperre aktivieren',
    accessTitle: 'Digitales Register entsperren',
  ),
);

String biometricAvailabilityMessage(CanAuthenticateResponse response) {
  switch (response) {
    case CanAuthenticateResponse.success:
      return tr('profile.biometricAvailable');
    case CanAuthenticateResponse.errorHwUnavailable:
      return tr('profile.biometricHwUnavailable');
    case CanAuthenticateResponse.errorNoBiometricEnrolled:
      return tr('profile.biometricNoEnrolled');
    case CanAuthenticateResponse.errorNoHardware:
      return tr('profile.biometricNoHardware');
    case CanAuthenticateResponse.errorPasscodeNotSet:
      return tr('profile.biometricPasscodeMissing');
    case CanAuthenticateResponse.statusUnknown:
      return tr('profile.biometricUnknown');
    case CanAuthenticateResponse.unsupported:
      return tr('profile.biometricUnsupported');
  }
}

class BiometricAppLockSetupException implements Exception {
  const BiometricAppLockSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BiometricAppLockController extends ChangeNotifier {
  bool _enabled = false;
  bool _locked = false;
  bool _hasSyncedSettings = false;
  Future<bool>? _pendingAuthentication;

  bool get isEnabled => _enabled;
  bool get isLocked => _locked;
  bool get isAuthenticating => _pendingAuthentication != null;

  Future<CanAuthenticateResponse> checkAvailability() async {
    try {
      return await BiometricStorage().canAuthenticate();
    } catch (_) {
      return CanAuthenticateResponse.unsupported;
    }
  }

  void syncEnabled(bool enabled) {
    if (!_hasSyncedSettings) {
      _hasSyncedSettings = true;
      _enabled = enabled;
      _locked = enabled;
      notifyListeners();
      return;
    }
    if (_enabled == enabled) {
      return;
    }
    _enabled = enabled;
    _locked = enabled;
    notifyListeners();
  }

  Future<void> enable() async {
    final availability = await checkAvailability();
    if (availability != CanAuthenticateResponse.success) {
      throw BiometricAppLockSetupException(
        biometricAvailabilityMessage(availability),
      );
    }

    try {
      final storage = await _getStorage();
      await storage.write(_appLockEnabledMarker);
      _hasSyncedSettings = true;
      _enabled = true;
      _locked = false;
      notifyListeners();
    } on AuthException catch (error) {
      if (error.code == AuthExceptionCode.userCanceled ||
          error.code == AuthExceptionCode.canceled) {
        throw BiometricAppLockSetupException(
          tr('profile.biometricSetupCancelled'),
        );
      }
      throw BiometricAppLockSetupException(
        tr('profile.biometricSetupFailed'),
      );
    } catch (_) {
      throw BiometricAppLockSetupException(
        tr('profile.biometricSetupFailed'),
      );
    }
  }

  Future<void> disable() async {
    _hasSyncedSettings = true;
    _enabled = false;
    _locked = false;
    notifyListeners();

    try {
      final storage = await _getStorage();
      await storage.delete();
    } catch (_) {
      // If cleanup fails we still disable the app-side lock state.
    }
  }

  void lock() {
    if (!_enabled || _locked) {
      return;
    }
    _locked = true;
    notifyListeners();
  }

  Future<bool> authenticateIfNeeded() {
    if (!_enabled || !_locked) {
      return Future.value(true);
    }
    final pending = _pendingAuthentication;
    if (pending != null) {
      return pending;
    }

    final future = _authenticate().whenComplete(() {
      _pendingAuthentication = null;
      notifyListeners();
    });
    _pendingAuthentication = future;
    notifyListeners();
    return future;
  }

  Future<bool> _authenticate() async {
    try {
      final storage = await _getStorage();
      final value = await storage.read();
      if (value == _appLockEnabledMarker) {
        _locked = false;
        notifyListeners();
        return true;
      }
    } on AuthException {
      return false;
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<BiometricStorageFile> _getStorage() {
    return BiometricStorage().getStorage(
      _appLockStorageName,
      options: StorageFileInitOptions(),
      promptInfo: _appLockPromptInfo,
    );
  }
}

final biometricAppLockController = BiometricAppLockController();

class AppLockSync extends StatefulWidget {
  const AppLockSync({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<AppLockSync> createState() => _AppLockSyncState();
}

class _AppLockSyncState extends State<AppLockSync> {
  @override
  void initState() {
    super.initState();
    biometricAppLockController.syncEnabled(widget.enabled);
    _scheduleInitialUnlockIfNeeded();
  }

  @override
  void didUpdateWidget(covariant AppLockSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      biometricAppLockController.syncEnabled(widget.enabled);
      _scheduleInitialUnlockIfNeeded();
    }
  }

  void _scheduleInitialUnlockIfNeeded() {
    if (!widget.enabled || !biometricAppLockController.isLocked) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(biometricAppLockController.authenticateIfNeeded());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class BiometricAppLockOverlay extends StatelessWidget {
  const BiometricAppLockOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: biometricAppLockController,
      builder: (context, _) {
        return Stack(
          children: [
            child,
            if (biometricAppLockController.isLocked)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fingerprint_rounded,
                                  size: 56,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  tr('profile.locked.title'),
                                  style:
                                      Theme.of(context).textTheme.headlineSmall,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  tr('profile.locked.body'),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: biometricAppLockController
                                          .isAuthenticating
                                      ? null
                                      : () {
                                          unawaited(
                                            biometricAppLockController
                                                .authenticateIfNeeded(),
                                          );
                                        },
                                  icon: biometricAppLockController
                                          .isAuthenticating
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.lock_open_rounded),
                                  label: Text(
                                    biometricAppLockController.isAuthenticating
                                        ? tr('profile.locked.checking')
                                        : tr('profile.locked.unlock'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
