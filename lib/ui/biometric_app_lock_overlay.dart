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

import 'package:dr/biometric_app_lock.dart';
import 'package:dr/main.dart';
import 'package:flutter/material.dart';

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
