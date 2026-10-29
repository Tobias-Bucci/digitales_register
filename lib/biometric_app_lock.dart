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
import 'package:dr/runtime_trace.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _appLockStorageName = 'biometric_app_lock';
const _appLockEnabledMarker = 'enabled';

/// Android app lock prompt implemented by [BiometricAppLockChannel].
const _androidAppLockChannel = MethodChannel('dr/biometric_app_lock');

/// Android authenticates the app lock through its own prompt instead of the
/// encrypted marker that `biometric_storage` stores.
///
/// The plugin protects its storage file with a keystore key created for strong
/// (Class 3) biometrics, and androidx refuses crypto-based authentication with
/// weak (Class 2) biometrics. Android reports most face unlock implementations
/// as Class 2, so a device that only offers face unlock could not use the app
/// lock through the plugin at all.
///
/// `BiometricManager.Authenticators.BIOMETRIC_WEAK` accepts Class 2 and Class 3
/// biometrics: fingerprint, iris, and face unlock when the OEM classifies it as
/// Class 2 or stronger. It does *not* accept Class 1 (convenience) face
/// recognition, which some devices allow for screen unlock only, so not every
/// device with face unlock can use this lock.
///
/// Security tradeoff: this path never touches the keystore. The lock succeeds
/// when the platform prompt reports a successful authentication, and no secret
/// is protected by the biometric. A modified build, or a hook that answers
/// [_androidAppLockChannel] with `true`, therefore unlocks the app without any
/// biometric; the enabled flag is likewise a plain `SharedPreferences` value.
/// This matches what the lock already is on every platform: a UI gate in front
/// of an already unlocked device, not an encryption boundary. It is still
/// weaker than the marker read on iOS and macOS, where the biometric is bound to
/// the keystore entry that holds the marker, so keep that in mind before adding
/// secrets behind the lock on Android.
bool get _usesAndroidAppLock =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
    if (_usesAndroidAppLock) {
      try {
        final response = await _androidAppLockChannel
            .invokeMethod<String>('canAuthenticate');
        return CanAuthenticateResponse.values.firstWhere(
          (value) => value.name == response,
          orElse: () => CanAuthenticateResponse.unsupported,
        );
      } catch (_) {
        return CanAuthenticateResponse.unsupported;
      }
    }
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

    if (_usesAndroidAppLock) {
      final bool authenticated;
      try {
        authenticated = await _authenticateOnAndroid();
      } on PlatformException catch (error) {
        throw BiometricAppLockSetupException(
          error.code == 'canceled'
              ? tr('profile.biometricSetupCancelled')
              : tr('profile.biometricSetupFailed'),
        );
      }
      if (!authenticated) {
        // Without an explicit success the lock must not be enabled.
        throw BiometricAppLockSetupException(
          tr('profile.biometricSetupFailed'),
        );
      }
      _hasSyncedSettings = true;
      _enabled = true;
      _locked = false;
      notifyListeners();
      return;
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
    if (_usesAndroidAppLock) {
      try {
        if (!await _authenticateOnAndroid()) {
          return false;
        }
      } catch (_) {
        return false;
      }
      _locked = false;
      notifyListeners();
      return true;
    }

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

  /// Shows the Android prompt and reports whether it explicitly succeeded.
  ///
  /// Only `true` counts as success: `false`, `null` and a missing result all mean
  /// the user did not authenticate, so the app stays locked and enabling the
  /// lock fails.
  Future<bool> _authenticateOnAndroid() async {
    final timer = Stopwatch()..start();
    runtimeTrace('AppStartup', 'biometric-prompt-start');
    final promptInfo = _appLockPromptInfo.androidPromptInfo;
    try {
      final authenticated = await _androidAppLockChannel.invokeMethod<bool>(
        'authenticate',
        <String, dynamic>{
          'title': promptInfo.title,
          'subtitle': promptInfo.subtitle,
          'description': promptInfo.description,
          'negativeButton': promptInfo.negativeButton,
          'confirmationRequired': promptInfo.confirmationRequired,
        },
      );
      return authenticated == true;
    } finally {
      runtimeTrace('AppStartup', 'biometric-prompt-end',
          durationMs: timer.elapsedMilliseconds);
    }
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

class BiometricAppLockOverlay extends StatefulWidget {
  const BiometricAppLockOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<BiometricAppLockOverlay> createState() =>
      _BiometricAppLockOverlayState();
}

class _BiometricAppLockOverlayState extends State<BiometricAppLockOverlay> {
  bool _wasLocked = false;

  /// The protected node that had focus when the app locked, restored once the
  /// app is unlocked again.
  FocusNode? _focusBeforeLock;

  @override
  void initState() {
    super.initState();
    _wasLocked = biometricAppLockController.isLocked;
    biometricAppLockController.addListener(_lockChanged);
  }

  @override
  void dispose() {
    biometricAppLockController.removeListener(_lockChanged);
    super.dispose();
  }

  void _lockChanged() {
    final locked = biometricAppLockController.isLocked;
    if (locked == _wasLocked) {
      return;
    }
    _wasLocked = locked;
    if (locked) {
      // Remember the focused protected node before ExcludeFocus drops its
      // focus in the next build.
      _focusBeforeLock = FocusManager.instance.primaryFocus;
      return;
    }
    final previous = _focusBeforeLock;
    _focusBeforeLock = null;
    if (previous == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          biometricAppLockController.isLocked ||
          previous.context == null ||
          !previous.canRequestFocus) {
        return;
      }
      previous.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: biometricAppLockController,
      builder: (context, _) {
        final locked = biometricAppLockController.isLocked;
        return Stack(
          children: [
            // While locked the protected content can neither keep nor gain
            // focus, so hardware keys, shortcuts and focus traversal cannot
            // reach it, and pointer input is ignored as well.
            ExcludeFocus(
              excluding: locked,
              child: IgnorePointer(
                ignoring: locked,
                child: widget.child,
              ),
            ),
            if (locked)
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
