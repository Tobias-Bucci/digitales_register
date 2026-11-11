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

/// Profile and change email in the new design. Their state classes in
/// `profile.dart` and `change_email.dart` keep the logic and build these views
/// below the shell; the legacy views stay as they are.
library;

import 'package:dr/app_state.dart';
import 'package:dr/config.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/profile_picture.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The text of [value], or null if it holds nothing but blanks.
String? _filled(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Whether the profile has arrived: the server sends a name or at least the
/// user name. Either is enough to show the page.
bool profileLoaded(ProfileState profile) =>
    _filled(profile.name) != null || _filled(profile.username) != null;

/// A text field on a [GlassCard]: a calm fill that keeps its contrast on the
/// light, the dark and the AMOLED theme, the accent while it has the focus.
InputDecoration glassFieldDecoration(
  BuildContext context, {
  String? labelText,
  String? hintText,
  String? errorText,
  Widget? suffixIcon,
}) {
  final scheme = Theme.of(context).colorScheme;
  final highContrast = MediaQuery.highContrastOf(context);
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    errorText: errorText,
    errorMaxLines: 3,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: highContrast
        ? scheme.surface
        : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
    labelStyle: TextStyle(color: scheme.onSurfaceVariant),
    hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    border: border(scheme.outlineVariant),
    enabledBorder:
        border(highContrast ? scheme.outline : scheme.outlineVariant),
    disabledBorder: border(scheme.onSurface.withValues(alpha: 0.12)),
    focusedBorder: border(scheme.primary, 2),
    errorBorder: border(scheme.error),
    focusedErrorBorder: border(scheme.error, 2),
  );
}

/// A switch on a [GlassCard], aligned with the rows of [GlassTile].
class _GlassSwitch extends StatelessWidget {
  const _GlassSwitch({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitle = this.subtitle;
    final enabled = onChanged != null;
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        // The title starts where that of a [GlassTile] does.
        child: ListTileTheme.merge(
          minLeadingWidth: 20,
          horizontalTitleGap: 8,
          child: SwitchListTile.adaptive(
            value: value,
            onChanged: onChanged,
            shape: const RoundedRectangleBorder(
              borderRadius: DesignTokens.cardBorderRadius,
            ),
            contentPadding: const EdgeInsetsDirectional.only(start: 10, end: 8),
            visualDensity: VisualDensity.standard,
            secondary: Icon(
              icon,
              size: 20,
              color: enabled
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.38),
            ),
            title: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: subtitle == null
                ? null
                : Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The profile of the new design: who is signed in, with the picture, and
/// below that what can be changed about the account.
class ProfileNewView extends StatelessWidget {
  const ProfileNewView({
    super.key,
    required this.profileState,
    required this.baseUrl,
    required this.noInternet,
    required this.uploadInProgress,
    required this.onUploadPicture,
    required this.changeEmail,
    required this.changePass,
    required this.setSendNotificationEmails,
    required this.biometricAppLockEnabled,
    required this.biometricSubtitle,
    required this.onBiometricChanged,
    required this.codiceFiscaleController,
    required this.hasCodiceFiscale,
    required this.codiceFiscaleSaving,
    required this.onCodiceFiscaleChanged,
    required this.onSaveCodiceFiscale,
  });

  final ProfileState profileState;
  final String? baseUrl;
  final bool noInternet;
  final bool uploadInProgress;
  final VoidCallback onUploadPicture;
  final VoidCallback changeEmail, changePass;
  final ValueChanged<bool> setSendNotificationEmails;
  final bool biometricAppLockEnabled;
  final String biometricSubtitle;

  /// Null while the lock cannot be switched.
  final ValueChanged<bool>? onBiometricChanged;
  final TextEditingController codiceFiscaleController;
  final bool hasCodiceFiscale, codiceFiscaleSaving;
  final ValueChanged<String> onCodiceFiscaleChanged;

  /// Null while there is nothing to save.
  final VoidCallback? onSaveCodiceFiscale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loaded = profileLoaded(profileState);
    return GlassPage(
      loading: !loaded && !noInternet,
      header: GlassPageHeader(
        surfaceKey: const Key('profile-app-header'),
        titleKey: const Key('profile-header-title'),
        title: l10n.text('profile.title'),
        floatingMaxWidth:
            glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width),
      ),
      body: !loaded
          ? GlassStateCard(
              key: Key(noInternet ? 'profile-offline' : 'profile-loading'),
              icon: noInternet
                  ? Icons.wifi_off_rounded
                  : Icons.person_outline_rounded,
              title: l10n.text(noInternet ? 'offline.title' : 'profile.title'),
              body: l10n.text(noInternet ? 'offline.body' : 'login.loading'),
            )
          : Builder(builder: _content),
    );
  }

  Widget _content(BuildContext context) {
    final l10n = context.l10n;
    final email = _filled(profileState.email);
    return GlassListBody(
      listKey: const Key('profile-list'),
      children: [
        _IdentityCard(
          profileState: profileState,
          baseUrl: baseUrl,
          uploadInProgress: uploadInProgress,
          onUploadPicture:
              noInternet || uploadInProgress ? null : onUploadPicture,
        ),
        const SizedBox(height: 8),
        GlassSectionHeading(title: l10n.text('settings.section.auth')),
        GlassTile(
          key: const Key('profile-change-email'),
          icon: Icons.alternate_email_rounded,
          title: l10n.text('profile.changeEmail'),
          subtitle: email,
          trailing: const Icon(Icons.chevron_right_rounded),
          enabled: !noInternet,
          onTap: changeEmail,
        ),
        const SizedBox(height: 8),
        GlassTile(
          key: const Key('profile-change-password'),
          icon: Icons.password_rounded,
          title: l10n.text('profile.changePassword'),
          trailing: const Icon(Icons.chevron_right_rounded),
          enabled: !noInternet,
          onTap: changePass,
        ),
        const SizedBox(height: 8),
        _GlassSwitch(
          key: const Key('profile-biometric-lock'),
          icon: Icons.fingerprint_rounded,
          title: l10n.text('profile.biometricLock'),
          subtitle: biometricSubtitle,
          value: biometricAppLockEnabled,
          onChanged: onBiometricChanged,
        ),
        const SizedBox(height: 8),
        GlassSectionHeading(title: l10n.text('notifications.title')),
        _GlassSwitch(
          key: const Key('profile-notification-emails'),
          icon: Icons.mark_email_unread_outlined,
          title: l10n.text('profile.notificationEmails'),
          value: profileState.sendNotificationEmails ?? false,
          onChanged: noInternet ? null : setSendNotificationEmails,
        ),
        const SizedBox(height: 8),
        GlassSectionHeading(title: l10n.text('profile.taxIdTitle')),
        _TaxIdCard(
          controller: codiceFiscaleController,
          locked: hasCodiceFiscale,
          saving: codiceFiscaleSaving,
          enabled: !noInternet,
          onChanged: onCodiceFiscaleChanged,
          onSave: onSaveCodiceFiscale,
        ),
      ],
    );
  }
}

/// The picture, the name and the account, and the way to a new picture.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.profileState,
    required this.baseUrl,
    required this.uploadInProgress,
    required this.onUploadPicture,
  });

  final ProfileState profileState;
  final String? baseUrl;
  final bool uploadInProgress;
  final VoidCallback? onUploadPicture;

  /// From here the picture stands beside the name.
  static const double _rowWidth = 520;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final username = _filled(profileState.username);
    final name = _filled(profileState.name) ?? username;
    final role = _filled(profileState.roleName);
    final school = _filled(schoolNameForUrl(baseUrl));
    final details = [
      if (role != null) l10n.translateProfileRole(role),
      if (username != null && username != name) username,
    ].join(' · ');
    final imageUrl = buildProfilePictureUrl(
      baseUrl: baseUrl,
      picture: profileState.picture,
    );
    final upload = FilledButton.icon(
      key: const Key('profile-upload-picture'),
      style: glassControlStyle(theme.colorScheme),
      onPressed: onUploadPicture,
      icon: uploadInProgress
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add_a_photo_outlined, size: 20),
      label: Text(
        l10n.text(
          uploadInProgress
              ? 'profile.uploadingPicture'
              : 'profile.uploadPicture',
        ),
      ),
    );
    return GlassCard(
      key: const Key('profile-identity'),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _rowWidth;
          final align = wide ? TextAlign.start : TextAlign.center;
          final texts = MergeSemantics(
            child: Column(
              crossAxisAlignment:
                  wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (name != null)
                  Text(
                    name,
                    key: const Key('profile-name'),
                    textAlign: align,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    details,
                    key: const Key('profile-details'),
                    textAlign: align,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (school != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    school,
                    key: const Key('profile-school'),
                    textAlign: align,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          );
          final avatar = ProfileAvatar(
            imageUrl: imageUrl,
            identity: ProfileIdentity(name: name, account: username),
            size: wide ? 96 : 88,
          );
          if (wide) {
            return Row(
              children: [
                avatar,
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      texts,
                      const SizedBox(height: 12),
                      upload,
                    ],
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              avatar,
              const SizedBox(height: 12),
              texts,
              const SizedBox(height: 14),
              upload,
            ],
          );
        },
      ),
    );
  }
}

/// The codice fiscale: a field and its save button, or the field locked with
/// the reason below it.
class _TaxIdCard extends StatelessWidget {
  const _TaxIdCard({
    required this.controller,
    required this.locked,
    required this.saving,
    required this.enabled,
    required this.onChanged,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool locked, saving, enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      key: const Key('profile-tax-id'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('profile-tax-id-field'),
            controller: controller,
            readOnly: locked,
            enabled: enabled,
            textCapitalization: TextCapitalization.characters,
            decoration: glassFieldDecoration(
              context,
              hintText: l10n.text('profile.taxIdHint'),
              suffixIcon: locked
                  ? Icon(Icons.lock_outline_rounded,
                      color: scheme.onSurfaceVariant)
                  : null,
            ),
            onChanged: onChanged,
          ),
          const SizedBox(height: 10),
          if (locked)
            Text(
              l10n.text('profile.taxIdLocked'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            )
          else
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                key: const Key('profile-save-tax-id'),
                onPressed: enabled && !saving ? onSave : null,
                child: saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.text('profile.saveTaxId')),
              ),
            ),
        ],
      ),
    );
  }
}

/// The form to change the email address in the new design: the password and
/// the new address, checked before anything is sent.
class ChangeEmailNewView extends StatelessWidget {
  const ChangeEmailNewView({
    super.key,
    required this.formKey,
    required this.passController,
    required this.emailController,
    required this.busy,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController passController, emailController;
  final bool busy, obscurePassword;
  final VoidCallback onToggleObscure, onSubmit;

  /// Keeps the save button above the keyboard when a field scrolls into view.
  static const _scrollPadding = EdgeInsets.fromLTRB(20, 20, 20, 120);

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Why [email] cannot be sent, or null if it can.
  static String? validateEmail(BuildContext context, String? email) {
    final value = email?.trim() ?? '';
    if (value.isEmpty) return context.t('login.emptyCredentials');
    if (!_emailPattern.hasMatch(value)) {
      return context.t('changeEmail.invalidEmail');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GlassPage(
      loading: busy,
      header: GlassPageHeader(
        surfaceKey: const Key('change-email-app-header'),
        titleKey: const Key('change-email-header-title'),
        title: l10n.text('profile.changeEmail'),
        floatingMaxWidth:
            glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width),
      ),
      body: GlassListBody(
        listKey: const Key('change-email-list'),
        children: [
          GlassCard(
            key: const Key('change-email-form'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Form(
              key: formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('change-email-password'),
                      controller: passController,
                      obscureText: obscurePassword,
                      enabled: !busy,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.next,
                      scrollPadding: _scrollPadding,
                      decoration: glassFieldDecoration(
                        context,
                        labelText: l10n.text('changeEmail.currentPassword'),
                        suffixIcon: IconButton(
                          tooltip: l10n.text(obscurePassword
                              ? 'login.showPassword'
                              : 'login.hidePassword'),
                          onPressed: busy ? null : onToggleObscure,
                          icon: Icon(obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        ),
                      ),
                      validator: (value) => (value ?? '').isEmpty
                          ? l10n.text('login.emptyCredentials')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('change-email-address'),
                      controller: emailController,
                      enabled: !busy,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                      scrollPadding: _scrollPadding,
                      decoration: glassFieldDecoration(
                        context,
                        labelText: l10n.text('changeEmail.newEmail'),
                      ),
                      validator: (value) => validateEmail(context, value),
                      onFieldSubmitted: (_) => onSubmit(),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton.icon(
                        key: const Key('change-email-submit'),
                        onPressed: busy ? null : onSubmit,
                        icon: busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_rounded, size: 20),
                        label: Text(l10n.text('button.save')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
