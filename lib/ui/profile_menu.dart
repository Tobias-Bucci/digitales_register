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

import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/profile_avatar.dart';
import 'package:dr/ui/sidebar.dart';
import 'package:flutter/material.dart';

/// Everything the header and footer of the sidebar offer, behind the profile
/// picture of the new design.
class ProfileMenu extends StatelessWidget {
  const ProfileMenu({
    super.key,
    required this.name,
    required this.username,
    required this.account,
    required this.userIcon,
    required this.otherAccounts,
    required this.showProfile,
    required this.showSettings,
    required this.selectAccount,
    required this.addAccount,
    required this.removeCurrentAccount,
    required this.logout,
  });

  final String? name, username;

  /// The account, shown below [name]: user name and school.
  final String? account;
  final String? userIcon;
  final List<String> otherAccounts;
  final VoidCallback showProfile, showSettings, addAccount;
  final VoidCallback removeCurrentAccount, logout;
  final SelectAccountCallback selectAccount;

  /// Closes the menu before [action], so that a page it opens is not covered.
  VoidCallback _closingFirst(BuildContext context, VoidCallback action) => () {
        Navigator.of(context).pop();
        action();
      };

  Future<void> _confirmLogout(BuildContext context) async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.text('profileMenu.logout.title')),
        content: Text(l10n.text('profileMenu.logout.body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.text('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.text('sidebar.logout')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      navigator.pop();
      logout();
    }
  }

  Future<void> _confirmRemoveAccount(BuildContext context) async {
    final navigator = Navigator.of(context);
    final confirmed = await confirmRemoveAccount(context, name);
    if (confirmed) {
      navigator.pop();
      removeCurrentAccount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: l10n.text('profileMenu.openProfile'),
            child: InkWell(
              key: const Key('profile-menu-header'),
              onTap: _closingFirst(context, showProfile),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    ProfileAvatar(
                      imageUrl: userIcon,
                      identity: ProfileIdentity(
                        name: name,
                        account: username,
                      ),
                      size: 48,
                      showProgress: false,
                    ),
                    const SizedBox(width: DesignTokens.gutter),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name ?? '?',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (account != null)
                            Text(
                              account!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          _MenuEntry(
            key: const Key('profile-menu-settings'),
            icon: Icons.tune,
            label: l10n.text('sidebar.settings'),
            onTap: _closingFirst(context, showSettings),
          ),
          for (var index = 0; index < otherAccounts.length; index++)
            _MenuEntry(
              key: ValueKey('profile-menu-account-$index'),
              icon: Icons.switch_account_rounded,
              leading: ProfileAvatar(
                imageUrl: null,
                identity: ProfileIdentity(
                  name: otherAccounts[index],
                  account: otherAccounts[index],
                ),
                size: 28,
              ),
              label: otherAccounts[index],
              tooltip: l10n.text('sidebar.switchAccount'),
              onTap: _closingFirst(context, () => selectAccount(index)),
            ),
          _MenuEntry(
            key: const Key('profile-menu-add-account'),
            icon: Icons.person_add_alt_1,
            label: l10n.text('sidebar.addAccount'),
            onTap: _closingFirst(context, addAccount),
          ),
          const Divider(height: 1),
          _MenuEntry(
            key: const Key('profile-menu-remove-account'),
            icon: Icons.person_remove_outlined,
            label: l10n.text('login.removeAccount'),
            onTap: () => _confirmRemoveAccount(context),
          ),
          _MenuEntry(
            key: const Key('profile-menu-logout'),
            icon: Icons.logout_rounded,
            label: l10n.text('sidebar.logout'),
            onTap: () => _confirmLogout(context),
          ),
        ],
      ),
    );
  }
}

class _MenuEntry extends StatelessWidget {
  const _MenuEntry({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tooltip,
    this.leading,
  });

  final IconData icon;

  /// Takes the place of [icon].
  final Widget? leading;
  final String label;
  final String? tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      leading: leading ?? Icon(icon),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
    return tooltip == null ? tile : Tooltip(message: tooltip, child: tile);
  }
}
