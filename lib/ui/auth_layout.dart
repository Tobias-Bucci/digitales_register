// Copyright (C) 2026 Tobias Bucci
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dr/i18n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Styling is scoped to authentication routes; the rest of the app keeps its theme.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.children,
    this.showAppBar = false,
    this.allowBack = true,
    this.loading = false,
  });

  final String title;
  final List<Widget> children;
  final bool showAppBar, allowBack, loading;

  static const fieldGap = SizedBox(height: 16);
  static const sectionGap = SizedBox(height: 24);
  static const radius = BorderRadius.all(Radius.circular(14));

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final colors = base.colorScheme;
    const border = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    );
    final theme = base.copyWith(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: BorderSide(color: colors.error, width: 2),
        ),
        errorMaxLines: 4,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: const RoundedRectangleBorder(borderRadius: radius),
          textStyle: base.textTheme.titleSmall,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: colors.surface,
        appBar: showAppBar
            ? AppBar(
                automaticallyImplyLeading: allowBack,
                backgroundColor: colors.surface,
                scrolledUnderElevation: 0,
                shape: const Border(),
              )
            : null,
        body: Stack(
          children: [
            SafeArea(
              child: LayoutBuilder(builder: (context, constraints) {
                final horizontalPadding =
                    constraints.maxWidth < 360 ? 16.0 : 24.0;
                return SingleChildScrollView(
                  key: const ValueKey('auth-scroll'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: constraints.maxHeight < 600 ? 24 : 40,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 448),
                          child: FocusTraversalGroup(
                            child: AutofillGroup(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.asset(
                                          'assets/Icon-App-512x512.png',
                                          width: 40,
                                          height: 40,
                                          excludeFromSemantics: true,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          context.l10n.text('login.appTitle'),
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  sectionGap,
                                  Semantics(
                                    header: true,
                                    child: Text(title,
                                        style: theme.textTheme.headlineMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        )),
                                  ),
                                  sectionGap,
                                  ...children,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            if (loading)
              LinearProgressIndicator(
                semanticsLabel: context.l10n.text('login.loading'),
              ),
          ],
        ),
      ),
    );
  }
}

class AuthMessage extends StatelessWidget {
  const AuthMessage(this.text,
      {super.key, this.isError = false, this.isStatus = false});

  final String text;
  final bool isError, isStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground =
        isError ? colors.onErrorContainer : colors.onSurfaceVariant;
    return Semantics(
      liveRegion: isError || isStatus,
      child: Container(
        decoration: BoxDecoration(
          color: isError ? colors.errorContainer : colors.surfaceContainerLow,
          borderRadius: AuthLayout.radius,
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
                isError
                    ? Icons.error_outline
                    : isStatus
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                size: 20,
                color: foreground),
            const SizedBox(width: 12),
            Expanded(
                child: Text(text,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: foreground))),
          ],
        ),
      ),
    );
  }
}

class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.isNewPassword = false,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled, isNewPassword;
  final String? errorText;
  final ValueChanged<String>? onChanged, onSubmitted;
  final TextInputAction textInputAction;

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: _obscured,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: widget.enabled
          ? [
              if (widget.isNewPassword)
                AutofillHints.newPassword
              else
                AutofillHints.password,
            ]
          : null,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          tooltip: context.l10n
              .text(_obscured ? 'login.showPassword' : 'login.hidePassword'),
          onPressed: widget.enabled
              ? () => setState(() => _obscured = !_obscured)
              : null,
          icon: Icon(_obscured
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined),
        ),
      ),
    );
  }
}
