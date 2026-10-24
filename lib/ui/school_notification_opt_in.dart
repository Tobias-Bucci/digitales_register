import 'dart:async';

import 'package:dr/biometric_app_lock.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/school_notification_engine.dart';
import 'package:dr/school_notification_service.dart';
import 'package:dr/tutorial/tutorial_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Startup notices finish before optional account onboarding starts.
final schoolNotificationStartupReady = ValueNotifier(false);

class SchoolNotificationOptInHost extends StatefulWidget {
  const SchoolNotificationOptInHost(
      {super.key,
      required this.signedIn,
      required this.account,
      required this.child,
      this.service,
      this.ready});
  final bool signedIn;
  final String? account;
  final Widget child;
  final SchoolNotificationService? service;
  final ValueListenable<bool>? ready;
  @override
  State<SchoolNotificationOptInHost> createState() =>
      _SchoolNotificationOptInHostState();
}

class _SchoolNotificationOptInHostState
    extends State<SchoolNotificationOptInHost> with WidgetsBindingObserver {
  SchoolNotificationService get service =>
      widget.service ?? schoolNotifications;
  ValueListenable<bool> get ready =>
      widget.ready ?? schoolNotificationStartupReady;
  bool _scheduled = false;
  bool _checking = false;
  int? _finishedSession;
  SchoolNotificationOptInOffer? _offer;
  DialogRoute<void>? _route;

  @override
  void initState() {
    super.initState();
    service.addListener(_changed);
    ready.addListener(_changed);
    biometricAppLockController.addListener(_changed);
    tutorialService.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant SchoolNotificationOptInHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      (oldWidget.service ?? schoolNotifications).removeListener(_changed);
      service.addListener(_changed);
    }
    if (oldWidget.ready != widget.ready) {
      (oldWidget.ready ?? schoolNotificationStartupReady)
          .removeListener(_changed);
      ready.addListener(_changed);
    }
    _changed();
  }

  bool get _available =>
      mounted &&
      widget.signedIn &&
      ready.value &&
      !biometricAppLockController.isLocked &&
      !tutorialService.active &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  void _changed() {
    final offer = _offer;
    if (offer != null &&
        (!widget.signedIn ||
            widget.account != offer.account ||
            service.activeAccount != offer.account ||
            service.sessionGeneration != offer.generation)) {
      _dismiss();
    }
    _schedule();
  }

  void _dismiss() {
    final route = _route;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (route.isActive && navigator != null && navigator.mounted) {
        navigator.removeRoute(route);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _schedule() {
    if (_scheduled || _checking || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_available && _finishedSession != service.sessionGeneration) {
        unawaited(_check());
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _check() async {
    _checking = true;
    final generation = service.sessionGeneration;
    try {
      final offer =
          widget.account == null ? null : await service.pendingOptIn();
      if (!mounted || !_available || generation != service.sessionGeneration) {
        return;
      }
      if (offer != null && offer.account == widget.account) {
        _offer = offer;
        final route = DialogRoute<void>(
            context: context,
            settings: const RouteSettings(name: '/school-notification-opt-in'),
            barrierDismissible: false,
            builder: (_) => SchoolNotificationOptInDialog(
                accountLabel: offer.label,
                onDecision: (accept, grades, messages) async {
                  await service.decideOptIn(offer,
                      accept: accept, grades: grades, messages: messages);
                }));
        _route = route;
        await Navigator.of(context, rootNavigator: true).push(route);
      }
      if (!mounted ||
          !widget.signedIn ||
          generation != service.sessionGeneration) {
        return;
      }
      _finishedSession = generation;
      if (offer == null ||
          service.preferences.consent != SchoolNotificationConsent.unknown ||
          widget.account == null) {
        tutorialService.scheduleOffer(context,
            isCurrent: () =>
                mounted &&
                widget.signedIn &&
                ready.value &&
                !biometricAppLockController.isLocked);
      }
    } catch (_) {
      // Optional OS/storage integration cannot hold login or the dashboard.
      if (mounted && widget.signedIn) {
        _finishedSession = generation;
        tutorialService.scheduleOffer(context,
            isCurrent: () => mounted && widget.signedIn);
      }
    } finally {
      _route = null;
      _offer = null;
      _checking = false;
      if (mounted && _finishedSession != service.sessionGeneration) _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _schedule();
  }

  @override
  void dispose() {
    _dismiss();
    WidgetsBinding.instance.removeObserver(this);
    service.removeListener(_changed);
    ready.removeListener(_changed);
    biometricAppLockController.removeListener(_changed);
    tutorialService.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Register the route dependency so closing another modal retries onboarding.
    ModalRoute.of(context);
    _schedule();
    return widget.child;
  }
}

class SchoolNotificationOptInDialog extends StatefulWidget {
  const SchoolNotificationOptInDialog(
      {super.key, required this.accountLabel, required this.onDecision});
  final String accountLabel;
  final Future<void> Function(bool accept, bool grades, bool messages)
      onDecision;
  @override
  State<SchoolNotificationOptInDialog> createState() =>
      _SchoolNotificationOptInDialogState();
}

class _SchoolNotificationOptInDialogState
    extends State<SchoolNotificationOptInDialog> {
  bool _grades = true;
  bool _messages = true;
  bool _busy = false;
  bool _failed = false;
  Future<void> _decide(bool accept) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.onDecision(accept, _grades, _messages);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return PopScope(
        canPop: false,
        child: AlertDialog(
          scrollable: true,
          constraints: const BoxConstraints(maxWidth: 480),
          icon: CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(Icons.notifications_active_outlined,
                  size: 28, color: theme.colorScheme.onPrimaryContainer)),
          title: Text(l10n.text('schoolNotifications.optIn.title')),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.text('schoolNotifications.optIn.body')),
                if (widget.accountLabel.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(widget.accountLabel,
                          style: theme.textTheme.labelLarge)),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(l10n.text('schoolNotifications.optIn.grades')),
                    value: _grades,
                    onChanged:
                        _busy ? null : (v) => setState(() => _grades = v!)),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title:
                        Text(l10n.text('schoolNotifications.optIn.messages')),
                    value: _messages,
                    onChanged:
                        _busy ? null : (v) => setState(() => _messages = v!)),
                const SizedBox(height: 8),
                Text(l10n.text('schoolNotifications.optIn.privacy'),
                    style: theme.textTheme.bodySmall),
                if (_failed)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(l10n.text('schoolNotifications.optIn.failed'),
                          style: TextStyle(color: theme.colorScheme.error))),
              ]),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => _decide(false),
                child: Text(l10n.text('schoolNotifications.optIn.decline'))),
            FilledButton.icon(
                onPressed: _busy || (!_grades && !_messages)
                    ? null
                    : () => _decide(true),
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.notifications_outlined),
                label: Text(l10n.text('schoolNotifications.optIn.accept'))),
          ],
        ));
  }
}
