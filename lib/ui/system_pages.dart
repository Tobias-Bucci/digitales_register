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

/// The rare screens of the app itself, which open on the root navigator,
/// outside the shell of the new design: an error, a user type the app does not
/// support, and a route that does not exist. Each has its Legacy look and the
/// look of the new design, chosen by the setting.
library;

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart' show NewDesignTheme;
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

/// Whether the new design is chosen, for the places outside its shell, where
/// `ResponsiveNavigationScope.isActive` is always false: the root navigator
/// and what opens above the dashboard. Without a store, Legacy.
///
/// It reads the setting once; the places that use it are short-lived.
bool newDesignChosen(BuildContext context) {
  final store = context.getInheritedWidgetOfExactType<ReduxProvider>()?.store;
  return store is Store<AppState, AppStateBuilder, AppActions> &&
      !store.state.settingsState.legacyDesign;
}

/// What the app shows when something went wrong that it cannot handle: the
/// text of [messageKey] and a button to tell the developer ([onContact]).
class ErrorPage extends StatelessWidget {
  const ErrorPage({
    super.key,
    required this.messageKey,
    required this.onContact,
  });

  /// `error.session`, `error.parse` or `error.generic`.
  final String messageKey;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (newDesignChosen(context)) {
      return _SystemStatePage(
        key: const Key('error-page-new'),
        icon: Icons.error_outline_rounded,
        title: l10n.text('error.title'),
        body: l10n.text(messageKey),
        actionLabel: l10n.text('error.contact'),
        actionIcon: Icons.feedback_outlined,
        onAction: onContact,
      );
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red,
        title: Text(l10n.text('error.title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Center(
            child: ElevatedButton(
              onPressed: onContact,
              child: Text(l10n.text('error.contact')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(l10n.text(messageKey)),
          ),
        ],
      ),
    );
  }
}

/// Says that the app is only for students and parents, with a way to the
/// website of the register ([onOpenWebsite]) and one back.
class UserTypeUnsupportedPage extends StatelessWidget {
  const UserTypeUnsupportedPage({super.key, required this.onOpenWebsite});

  final VoidCallback onOpenWebsite;

  @override
  Widget build(BuildContext context) {
    if (newDesignChosen(context)) {
      return _SystemStatePage(
        key: const Key('user-type-unsupported-page-new'),
        icon: Icons.person_off_outlined,
        title: context.t('login.userTypeUnsupported.title'),
        body: context.t('login.userTypeUnsupported.message'),
        actionLabel: context.t('login.userTypeUnsupported.website'),
        actionIcon: Icons.open_in_new_rounded,
        onAction: onOpenWebsite,
        secondaryActions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('common.cancel')),
          ),
        ],
      );
    }
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.t('login.userTypeUnsupported.title'),
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.t('login.userTypeUnsupported.message'),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.t('common.cancel')),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: onOpenWebsite,
                  child: Text(context.t('login.userTypeUnsupported.website')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A route the app does not know, such as an old link: says which, and leads
/// to the start page.
class UnknownRoutePage extends StatelessWidget {
  const UnknownRoutePage({super.key, required this.routeName});

  final String routeName;

  void _goHome(BuildContext context) =>
      Navigator.of(context).pushReplacementNamed('/');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final body = l10n.text(
      'navigation.unknownRoute.body',
      args: {'route': routeName},
    );
    if (newDesignChosen(context)) {
      return _SystemStatePage(
        key: const Key('unknown-route-page-new'),
        icon: Icons.link_off_rounded,
        title: l10n.text('navigation.unknownRoute.title'),
        body: body,
        actionLabel: l10n.text('navigation.unknownRoute.action'),
        actionIcon: Icons.home_rounded,
        onAction: () => _goHome(context),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('navigation.unknownRoute.title'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.link_off_rounded,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => _goHome(context),
                child: Text(l10n.text('navigation.unknownRoute.action')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The frame of a system screen in the new design: the glass header with
/// only the way back, and the message as a [GlassStateCard] in the middle.
/// The title is the heading of the card, so it is not repeated above it.
class _SystemStatePage extends StatelessWidget {
  const _SystemStatePage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    this.secondaryActions = const [],
  });

  final IconData icon, actionIcon;
  final String title, body, actionLabel;
  final VoidCallback onAction;
  final List<Widget> secondaryActions;

  @override
  Widget build(BuildContext context) => NewDesignTheme(
        child: GlassPage(
          header: GlassPageHeader(
            surfaceKey: const Key('system-page-header'),
            title: title,
            titleWidget: const SizedBox.shrink(),
            floatingMaxWidth:
                glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width),
          ),
          body: GlassStateCard(
            icon: icon,
            title: title,
            body: body,
            actionLabel: actionLabel,
            actionIcon: actionIcon,
            onAction: onAction,
            secondaryActions: secondaryActions,
          ),
        ),
      );
}
