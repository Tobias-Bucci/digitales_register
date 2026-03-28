// Copyright (C) 2021 Michael Debertol
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

import 'package:collapsible_sidebar/collapsible_sidebar.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:flutter/material.dart';

typedef SelectAccountCallback = void Function(int index);

class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.drawerExpanded,
    required this.onDrawerExpansionChange,
    required this.username,
    required this.userIcon,
    required this.tabletMode,
    required this.goHome,
    required this.currentSelected,
    required this.showGrades,
    required this.showAbsences,
    required this.showCalendar,
    required this.showCertificate,
    required this.showMessages,
    required this.showSettings,
    required this.logout,
    required this.otherAccounts,
    required this.selectAccount,
    required this.addAccount,
    required this.passwordSavingEnabled,
  });

  final DrawerCallback onDrawerExpansionChange;
  final VoidCallback goHome,
      showGrades,
      showAbsences,
      showCalendar,
      showCertificate,
      showMessages,
      showSettings,
      logout,
      addAccount;
  final bool tabletMode, drawerExpanded, passwordSavingEnabled;
  final Pages currentSelected;
  final String? username, userIcon;
  final List<String> otherAccounts;
  final SelectAccountCallback selectAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return CollapsibleSidebar(
      onExpansionChange: onDrawerExpansionChange,
      alwaysExpanded: !tabletMode,
      expanded: drawerExpanded,
      iconSize: 26,
      textStyle: theme.textTheme.titleMedium,
      fitItemsToBottom: true,
      borderRadius: 0,
      minWidth: 74,
      screenPadding: 0,
      title: Container(
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: DropdownButtonHideUnderline(
          child: DropdownButton(
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            value: 0,
            items: [
              for (var index = 0; index < otherAccounts.length + 2; index++)
                DropdownMenuItem(
                  value: index,
                  child: Text(
                    index == 0
                        ? (username ?? "?")
                        : index <= otherAccounts.length
                            ? otherAccounts[index - 1]
                            : passwordSavingEnabled
                                ? "Account hinzufügen"
                                : "Account wechseln",
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (int? value) {
              if (value == 0) {
                // selected the current account that is already selected
                // no-op
              } else {
                scaffoldKey?.currentState?.closeDrawerIfOpen();
                if (value == otherAccounts.length + 1) {
                  addAccount();
                } else {
                  selectAccount(value! - 1);
                }
              }
            },
          ),
        ),
      ),
      titleTooltip: username ?? "?",
      toggleTooltipCollapsed: "Ausklappen",
      toggleTooltipExpanded: "Einklappen",
      toggleTitle: const SizedBox(),
      backgroundColor: scheme.surface,
      avatar:
          //"https://vinzentinum.digitalesregister.it/v2/theme/icons/profile_empty.png" is the (ugly) default
          userIcon?.endsWith("/profile_empty.png") ?? true
              ? CircleAvatar(
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  child: Icon(
                    Icons.account_circle,
                    color: scheme.primary,
                  ),
                )
              : ClipOval(child: Image.network(userIcon!)),
      unselectedIconColor: theme.iconTheme.color!,
      selectedIconColor: scheme.primary,
      unselectedTextColor: theme.textTheme.titleMedium!.color!,
      selectedTextColor: scheme.primary,
      selectedIconBox: scheme.primary.withValues(alpha: 0.12),
      items: [
        if (tabletMode)
          CollapsibleItem(
            isSelected: currentSelected == Pages.homework,
            icon: Icons.dashboard_outlined,
            text: "Hausaufgaben",
            onPressed: goHome,
          ),
        CollapsibleItem(
          onPressed: showGrades,
          isSelected: currentSelected == Pages.grades,
          text: "Noten",
          icon: Icons.auto_graph_outlined,
        ),
        CollapsibleItem(
            text: "Absenzen",
            icon: Icons.event_busy_outlined,
            isSelected: currentSelected == Pages.absences,
            onPressed: showAbsences),
        CollapsibleItem(
          text: "Kalender",
          icon: Icons.calendar_month_outlined,
          isSelected: currentSelected == Pages.calendar,
          onPressed: showCalendar,
        ),
        CollapsibleItem(
          text: "Zeugnis",
          icon: Icons.description_outlined,
          isSelected: currentSelected == Pages.certificate,
          onPressed: showCertificate,
        ),
        CollapsibleItem(
          text: "Mitteilungen",
          icon: Icons.mark_email_unread_outlined,
          isSelected: currentSelected == Pages.messages,
          onPressed: showMessages,
        ),
        CollapsibleItem(
          hasDivider: true,
          text: "Einstellungen",
          icon: Icons.tune,
          isSelected: currentSelected == Pages.settings,
          onPressed: showSettings,
        ),
        CollapsibleItem(
          hasDivider: true,
          text: "Abmelden",
          icon: Icons.logout_rounded,
          onPressed: logout,
        ),
      ],
      body: const SizedBox(),
    );
  }
}
