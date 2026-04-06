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

import 'dart:async';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:dr/app_state.dart';
import 'package:dr/biometric_app_lock.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/profile_picture.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/ui/user_profile.dart';
import 'package:flutter/material.dart';

typedef AsyncVoidCallback = Future<void> Function();
typedef UpdateCodiceFiscale = Future<void> Function(String codiceFiscale);

class Profile extends StatefulWidget {
  final ProfileState profileState;
  final String? baseUrl;
  final bool noInternet;
  final bool biometricAppLockEnabled;
  final OnSettingChanged<bool> setSendNotificationEmails;
  final OnSettingChanged<bool> setBiometricAppLockEnabled;
  final VoidCallback changeEmail;
  final VoidCallback changePass;
  final AsyncVoidCallback uploadProfilePicture;
  final UpdateCodiceFiscale updateCodiceFiscale;

  const Profile({
    super.key,
    required this.profileState,
    required this.baseUrl,
    required this.biometricAppLockEnabled,
    required this.setSendNotificationEmails,
    required this.setBiometricAppLockEnabled,
    required this.changeEmail,
    required this.changePass,
    required this.noInternet,
    required this.uploadProfilePicture,
    required this.updateCodiceFiscale,
  });

  @override
  State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> {
  late final TextEditingController _codiceFiscaleController;
  bool _uploadInProgress = false;
  bool _codiceFiscaleSaveInProgress = false;
  bool _biometricToggleInProgress = false;
  CanAuthenticateResponse? _biometricAvailability;

  @override
  void initState() {
    super.initState();
    _codiceFiscaleController = TextEditingController(
      text: widget.profileState.codiceFiscale ?? '',
    );
    unawaited(_loadBiometricAvailability());
  }

  @override
  void didUpdateWidget(covariant Profile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileState.codiceFiscale !=
        widget.profileState.codiceFiscale) {
      _codiceFiscaleController.text = widget.profileState.codiceFiscale ?? '';
    }
  }

  @override
  void dispose() {
    _codiceFiscaleController.dispose();
    super.dispose();
  }

  bool get _hasCodiceFiscale {
    final codiceFiscale = widget.profileState.codiceFiscale?.trim();
    return codiceFiscale != null && codiceFiscale.isNotEmpty;
  }

  String get _normalizedCodiceFiscale =>
      _codiceFiscaleController.text.trim().toUpperCase();

  bool get _biometricSupported =>
      _biometricAvailability == CanAuthenticateResponse.success;

  bool get _canToggleBiometricLock =>
      !_biometricToggleInProgress &&
      (widget.biometricAppLockEnabled || _biometricSupported);

  String get _biometricSubtitle {
    final l10n = context.l10n;
    if (_biometricToggleInProgress) {
      return widget.biometricAppLockEnabled
          ? l10n.text('profile.biometricDisabling')
          : l10n.text('profile.biometricEnabling');
    }
    if (_biometricAvailability == null) {
      return l10n.text('profile.biometricChecking');
    }
    return switch (_biometricAvailability!) {
      CanAuthenticateResponse.success => l10n.text('profile.biometricAvailable'),
      CanAuthenticateResponse.errorHwUnavailable =>
        l10n.text('profile.biometricHwUnavailable'),
      CanAuthenticateResponse.errorNoBiometricEnrolled =>
        l10n.text('profile.biometricNoEnrolled'),
      CanAuthenticateResponse.errorNoHardware =>
        l10n.text('profile.biometricNoHardware'),
      CanAuthenticateResponse.errorPasscodeNotSet =>
        l10n.text('profile.biometricPasscodeMissing'),
      CanAuthenticateResponse.statusUnknown =>
        l10n.text('profile.biometricUnknown'),
      CanAuthenticateResponse.unsupported =>
        l10n.text('profile.biometricUnsupported'),
    };
  }

  Future<void> _loadBiometricAvailability() async {
    final availability = await biometricAppLockController.checkAvailability();
    if (!mounted) {
      return;
    }
    setState(() {
      _biometricAvailability = availability;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _handleProfilePictureUpload() async {
    setState(() {
      _uploadInProgress = true;
    });
    try {
      await widget.uploadProfilePicture();
    } finally {
      if (mounted) {
        setState(() {
          _uploadInProgress = false;
        });
      }
    }
  }

  Future<void> _handleCodiceFiscaleSave() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _codiceFiscaleSaveInProgress = true;
    });
    try {
      await widget.updateCodiceFiscale(_normalizedCodiceFiscale);
    } finally {
      if (mounted) {
        setState(() {
          _codiceFiscaleSaveInProgress = false;
        });
      }
    }
  }

  Future<void> _handleBiometricAppLockChanged(bool enabled) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _biometricToggleInProgress = true;
    });
    try {
      if (enabled) {
        await biometricAppLockController.enable();
        if (!mounted) return;
        widget.setBiometricAppLockEnabled(true);
        _showMessage(context.t('profile.biometricEnabled'));
      } else {
        await biometricAppLockController.disable();
        if (!mounted) return;
        widget.setBiometricAppLockEnabled(false);
        _showMessage(context.t('profile.biometricDisabled'));
      }
    } on BiometricAppLockSetupException catch (error) {
      _showMessage(error.message);
    } finally {
      await _loadBiometricAvailability();
      if (mounted) {
        setState(() {
          _biometricToggleInProgress = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileState = widget.profileState;
    final imageUrl = buildProfilePictureUrl(
      baseUrl: widget.baseUrl,
      picture: profileState.picture,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('profile.title')),
      ),
      body: profileState.name == null
          ? Center(
              child: widget.noInternet
                  ? const NoInternet()
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: UserProfile(
                    name: profileState.name!,
                    username: profileState.username!,
                    role: context.l10n.translateProfileRole(
                      profileState.roleName!,
                    ),
                    imageUrl: imageUrl,
                    onUploadProfilePicture: _handleProfilePictureUpload,
                    uploadInProgress: _uploadInProgress,
                    uploadEnabled: !widget.noInternet,
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            context.t('profile.taxIdTitle'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _codiceFiscaleController,
                            readOnly: _hasCodiceFiscale,
                            enabled: !widget.noInternet,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              hintText: context.t('profile.taxIdHint'),
                            ),
                            onChanged: (_) {
                              if (!_hasCodiceFiscale) {
                                setState(() {});
                              }
                            },
                          ),
                          if (_hasCodiceFiscale) ...<Widget>[
                            const SizedBox(height: 12),
                            Text(
                              context.t('profile.taxIdLocked'),
                            ),
                          ] else ...<Widget>[
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: widget.noInternet ||
                                      _codiceFiscaleSaveInProgress ||
                                      _normalizedCodiceFiscale.isEmpty
                                  ? null
                                  : _handleCodiceFiscaleSave,
                              child: _codiceFiscaleSaveInProgress
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Text(context.t('profile.saveTaxId')),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                SwitchListTile.adaptive(
                  title: Text(context.t('profile.notificationEmails')),
                  value: profileState.sendNotificationEmails!,
                  onChanged: widget.noInternet
                      ? null
                      : widget.setSendNotificationEmails,
                ),
                ListTile(
                  title: Text(context.t('profile.changeEmail')),
                  subtitle: Text(profileState.email!),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.changeEmail,
                  enabled: !widget.noInternet,
                ),
                ListTile(
                  title: Text(context.t('profile.changePassword')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.changePass,
                  enabled: !widget.noInternet,
                ),
                const Divider(),
                SwitchListTile.adaptive(
                  title: Text(context.t('profile.biometricLock')),
                  subtitle: Text(_biometricSubtitle),
                  value: widget.biometricAppLockEnabled,
                  onChanged: _canToggleBiometricLock
                      ? _handleBiometricAppLockChanged
                      : null,
                ),
              ],
            ),
    );
  }
}
