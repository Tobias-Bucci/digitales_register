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

import 'package:collapsible_sidebar/collapsible_sidebar.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/app_popup_button.dart';
import 'package:dr/ui/profile_avatar.dart';
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
    required this.showProfile,
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
      showProfile,
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
    final accountEntries = <AppPopupButtonEntry<int>>[
      AppPopupButtonEntry<int>(
        value: 0,
        label: username ?? "?",
        leading: const Icon(Icons.person_outline_rounded, size: 20),
      ),
      for (var index = 0; index < otherAccounts.length; index++)
        AppPopupButtonEntry<int>(
          value: index + 1,
          label: otherAccounts[index],
          leading: const Icon(Icons.switch_account_rounded, size: 20),
        ),
      AppPopupButtonEntry<int>(
        value: otherAccounts.length + 1,
        label:
            passwordSavingEnabled ? "Account hinzufügen" : "Account wechseln",
        leading: Icon(
          passwordSavingEnabled ? Icons.person_add_alt_1 : Icons.login_rounded,
          size: 20,
        ),
      ),
    ];

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
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: AppPopupButton<int>(
          selectedValue: 0,
          expand: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          entries: accountEntries,
          labelBuilder: (_) => username ?? "?",
          onSelected: (value) {
            scaffoldKey?.currentState?.closeDrawerIfOpen();
            if (value == otherAccounts.length + 1) {
              addAccount();
            } else if (value != 0) {
              selectAccount(value - 1);
            }
          },
        ),
      ),
      titleTooltip: username ?? "?",
      toggleTooltipCollapsed: "Ausklappen",
      toggleTooltipExpanded: "Einklappen",
      toggleTitle: const SizedBox(),
      backgroundColor: scheme.surface,
      avatar: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          scaffoldKey?.currentState?.closeDrawerIfOpen();
          showProfile();
        },
        child: ProfileAvatar(
          imageUrl: userIcon,
          size: 56,
        ),
      ),
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
